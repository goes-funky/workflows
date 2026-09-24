"""Exercise the generated notification step with local AWS/GitHub command fakes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InfraDispatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = json.loads(subprocess.check_output(
            [str(ROOT / 'bin/cue'), 'export', 'pkg/workflows/notify-infra.cue', '--out', 'json'], cwd=ROOT))
        cls.script = next(step['run'] for step in workflow['jobs']['notify']['steps'] if step.get('id') == 'dispatch')

    def invoke(self, image, source_sha='abcdef0123456789', failures=0, aws_failure=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        commands = {
            'aws': '#!/bin/sh\n[ "$AWS_FAILURE" = 1 ] && exit 1\nprintf "read\\n" >> "$RUNNER_TEMP/aws-calls"\nprintf "%s" "test-only-dispatch-token"\n',
            'gh': '''#!/bin/sh
count=0
if [ -f "$RUNNER_TEMP/attempts" ]; then count=$(cat "$RUNNER_TEMP/attempts"); fi
count=$((count + 1))
printf '%s' "$count" > "$RUNNER_TEMP/attempts"
[ "$GH_TOKEN" = 'test-only-dispatch-token' ] || exit 99
if [ "$count" -le "$FAILURES" ]; then exit 1; fi
printf '%s\n' "$@" > "$RUNNER_TEMP/gh-args"
''',
            'sleep': '#!/bin/sh\nexit 0\n'
        }
        for name, body in commands.items():
            target = directory / name
            target.write_text(body)
            target.chmod(0o755)
        env = {**os.environ, 'PATH': f'{directory}:{os.environ["PATH"]}',
               'RUNNER_TEMP': str(directory), 'PUBLISHED_IMAGE': image,
               'EXPECTED_REGISTRY': '123456789012.dkr.ecr.eu-central-1.amazonaws.com',
               'GITHUB_REPOSITORY': 'goes-funky/modeling-api', 'GITHUB_SHA': source_sha,
               'GITHUB_SERVER_URL': 'https://github.com', 'GITHUB_RUN_ID': '123', 'FAILURES': str(failures), 'AWS_FAILURE': '1' if aws_failure else '0'}
        result = subprocess.run(['bash', '-c', self.script], env=env, capture_output=True, text=True)
        return result, directory

    def image(self, tag='abcdef0-202609241200'):
        return f'123456789012.dkr.ecr.eu-central-1.amazonaws.com/modeling-api:{tag}@sha256:{"a" * 64}'

    def test_dispatches_exact_image_to_both_environments(self):
        result, directory = self.invoke(self.image())
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads((directory / 'infra-dispatch.json').read_text())
        self.assertEqual(payload['ref'], 'main')
        self.assertEqual(payload['inputs'], {
            'service': 'modeling-api', 'environment': 'both', 'tag': 'abcdef0-202609241200',
            'digest': 'sha256:' + 'a' * 64, 'automatic': 'true', 'dry-run': 'false',
            'source-run': 'https://github.com/goes-funky/modeling-api/actions/runs/123'})
        self.assertIn('aws-image-update-branches.yaml/dispatches', (directory / 'gh-args').read_text())
        self.assertNotIn('test-only-dispatch-token', (directory / 'infra-dispatch.json').read_text())
        # The only token-bearing output is the runner's masking command.
        self.assertEqual([line for line in result.stdout.splitlines() if 'test-only-dispatch-token' in line],
                         ['::add-mask::test-only-dispatch-token'])

    def test_rejects_invalid_or_branch_images_before_reading_secret(self):
        for image in [self.image('abcdef0-202609241200-test'), self.image().split('@')[0],
                      self.image().replace('/modeling-api:', '/another-service:'), self.image() + '\nextra']:
            with self.subTest(image=image):
                result, directory = self.invoke(image)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((directory / 'aws-calls').exists())

    def test_rejects_image_from_another_commit_before_reading_secret(self):
        result, directory = self.invoke(self.image(), source_sha='bbbbbbb123456789')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((directory / 'aws-calls').exists())

    def test_missing_secret_stops_before_github_dispatch(self):
        result, directory = self.invoke(self.image(), aws_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((directory / 'attempts').exists())

    def test_retries_dispatch_without_rebuilding(self):
        result, directory = self.invoke(self.image(), failures=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((directory / 'attempts').read_text(), '3')
        result, directory = self.invoke(self.image(), failures=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((directory / 'attempts').read_text(), '3')


if __name__ == '__main__':
    unittest.main()
