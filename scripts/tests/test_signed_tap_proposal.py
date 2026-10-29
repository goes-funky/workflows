"""Run the generated proposal script; no GitHub or cluster operations occur."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILE = 'integrations/taps/google-adwords/dev/job_template.yaml'


class SignedProposalTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = json.loads(subprocess.check_output(
            [str(ROOT / 'bin/cue'), 'export', 'pkg/workflows/deploy-integration.cue', '--out', 'json'], cwd=ROOT))
        cls.script = next(s['run'] for s in workflow['jobs']['deploy-development']['steps']
                          if s['name'] == 'Propose tap image release')

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / '.integrations'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.file = self.repo / FILE
        self.file.parent.mkdir(parents=True)
        self.file.write_text('image: old\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD')
        self.file.write_text('image: new\n')
        helper = self.root / '.infra-signing/scripts/image-update-branches.js'
        helper.parent.mkdir(parents=True)
        helper.write_text('''const fs = require('node:fs')
module.exports = {
  fetchBranch: () => process.env.PREVIOUS_HEAD || '',
  pushSignedCommit: (...args) => {
    if (process.env.GITHUB_REPOSITORY !== 'goes-funky/integrations') throw new Error('Incorrect signing repository')
    fs.appendFileSync(process.env.CALLS, JSON.stringify(['sign', ...args]) + '\\n')
    if (process.env.SIGNING_FAILURE === '1') throw new Error('Signature or tree verification failed')
  }
}
''')
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f: f.write(json.dumps(['gh', *args]) + '\\n')
if args[0] == 'api':
    print(json.dumps({'commit': {'verification': {'verified': os.environ.get('VERIFIED') == '1'}}}))
elif args[:2] == ['pr', 'list']:
    print(json.dumps([{'number': 7, 'url': 'https://github.com/goes-funky/integrations/pull/7', 'headRefOid': os.environ.get('PREVIOUS_HEAD')}] if os.environ.get('EXISTING_PR') == '1' else []))
elif args[:2] == ['pr', 'create']:
    print('https://github.com/goes-funky/integrations/pull/7')
''')
        gh.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
                    'GH_TOKEN': 'test-token', 'GITHUB_REPOSITORY': 'goes-funky/tap-google-ads-container',
                    'TARGET_REPOSITORY': 'goes-funky/integrations',
                    'TARGET_ENVIRONMENT': 'dev', 'TAP_TEMPLATE': 'google-adwords',
                    'SOURCE_REPOSITORY': 'goes-funky/tap-google-ads-container', 'SOURCE_SHA': 'a' * 40,
                    'SOURCE_RUN': 'https://github.com/goes-funky/tap-google-ads-container/actions/runs/1',
                    'GITHUB_OUTPUT': str(self.root / 'output'), 'CALLS': str(self.root / 'calls')}

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True).strip()

    def invoke(self, **env):
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', self.script], cwd=self.root,
                                env={**self.env, **env}, capture_output=True, text=True)
        calls = self.root / 'calls'
        return result, [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []

    def previous_proposal(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'previous proposal')
        previous = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', self.base)
        self.file.write_text('image: new\n')
        return previous

    def test_signed_publication_precedes_ready_dev_pr(self):
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0], ['sign', 'tap-release/google-adwords/dev', self.base, '', [FILE]])
        create = next(c for c in calls if c[:3] == ['gh', 'pr', 'create'])
        self.assertIn('goes-funky/integrations', create)
        self.assertNotIn('goes-funky/tap-google-ads-container', create)
        self.assertNotIn('--draft', create)
        self.assertIn('flux-dev-update', create)
        self.assertIn('pull-request-url=https://', (self.root / 'output').read_text())

    def test_failed_signing_never_creates_or_updates_pr(self):
        result, calls = self.invoke(SIGNING_FAILURE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([c[0] for c in calls], ['sign'])
        self.assertFalse((self.root / 'output').exists())

    def test_unsigned_identical_previous_proposal_is_resigned(self):
        previous = self.previous_proposal()
        result, calls = self.invoke(PREVIOUS_HEAD=previous, VERIFIED='0', EXISTING_PR='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(next(c for c in calls if c[0] == 'sign')[3], previous)
        self.assertTrue(any(c[:3] == ['gh', 'pr', 'edit'] for c in calls))

    def test_verified_identical_proposal_is_idempotent(self):
        result, calls = self.invoke(PREVIOUS_HEAD=self.previous_proposal(), VERIFIED='1', EXISTING_PR='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[0] == 'sign' for c in calls))
        self.assertTrue(any(c[:3] == ['gh', 'pr', 'edit'] for c in calls))

    def test_unrelated_change_stops_before_publication(self):
        (self.repo / 'unrelated').write_text('base')
        self.git('add', 'unrelated')
        self.git('commit', '-qm', 'unrelated base')
        (self.repo / 'unrelated').write_text('modified')
        result, calls = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_no_change_does_not_publish(self):
        self.file.write_text('image: old\n')
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c[:3] for c in calls], [['gh', 'pr', 'list']])

    def test_no_change_does_not_close_a_proposal_with_unrelated_edits(self):
        (self.repo / 'unrelated').write_text('must not discard')
        self.git('add', '.')
        self.git('commit', '-qm', 'mixed proposal')
        previous = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', self.base)
        result, calls = self.invoke(PREVIOUS_HEAD=previous, EXISTING_PR='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[:3] == ['gh', 'pr', 'close'] for c in calls))

    def test_no_change_closes_only_the_matching_image_proposal(self):
        previous = self.previous_proposal()
        self.file.write_text('image: old\n')
        (self.repo / 'new-main-file').write_text('main advanced after proposal')
        self.git('add', 'new-main-file')
        self.git('commit', '-qm', 'advance main')
        validator = self.repo / 'scripts/update_tap_image.py'
        validator.parent.mkdir()
        validator.write_text('def validate_image_change(before, after):\n    assert before.startswith("image:") and after.startswith("image:")\n')
        result, calls = self.invoke(PREVIOUS_HEAD=previous, EXISTING_PR='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[0] == 'sign' for c in calls))
        self.assertTrue(any(c[:3] == ['gh', 'pr', 'close'] for c in calls))


if __name__ == '__main__':
    unittest.main()
