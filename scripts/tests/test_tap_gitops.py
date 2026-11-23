"""Exercise generated GitOps render/apply logic with fake cluster commands."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class GitOpsNoticeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = json.loads(subprocess.check_output(
            [str(ROOT / 'bin/cue'), 'export', 'pkg/workflows/deploy-integration.cue', '--out', 'json'], cwd=ROOT))
        cls.steps = cls.workflow['jobs']['deploy-development']['steps']
        cls.script = next(s['run'] for s in cls.steps if s['name'] == 'Publish OAuth settings for GitOps tap')

    def invoke(self, auth_only=True, extra_manifest=''):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        (directory / 'fixture.yaml').write_text('''apiVersion: v1
kind: ConfigMap
metadata:
  name: tap-google-ads-container-tap-config
---
apiVersion: batch/v1
kind: Job
metadata:
  name: tap-google-ads-container-deploy-notice
spec:
  template:
    spec:
      containers:
        - name: deploy-notice
          args:
            - python -m datos_integrations.commands.deploy_notice AUTH_FLAG
'''.replace('AUTH_FLAG', '--auth-only' if auth_only else '') + extra_manifest)
        for name, command in {
            'skaffold': '#!/bin/sh\nif [ "$1" = render ]; then cat fixture.yaml; else cp rendered.yaml applied.yaml; fi\n',
            'kubectl': '#!/bin/sh\ncat > waited.yaml\n',
        }.items():
            path = directory / name
            path.write_text(command)
            path.chmod(0o755)
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', self.script], cwd=directory,
                                env={**os.environ, 'PATH': f'{directory}:{os.environ["PATH"]}',
                                     'RELEASE_ID': '123-2'}, text=True, capture_output=True)
        return result, directory

    def test_applies_auth_notice_and_preserves_tap_config(self):
        result, directory = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        applied = (directory / 'applied.yaml').read_text()
        self.assertIn('tap-google-ads-container-tap-config', applied)
        self.assertIn('tap-google-ads-container-deploy-notice-123-2', applied)
        self.assertNotIn('ConfigMap', (directory / 'waited.yaml').read_text())

    def test_refuses_old_notice_before_apply(self):
        result, directory = self.invoke(auth_only=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((directory / 'applied.yaml').exists())

    def test_refuses_legacy_template_map_before_apply(self):
        result, directory = self.invoke(extra_manifest='''---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tap-google-ads-container-job-template
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((directory / 'applied.yaml').exists())

    def test_main_builds_release_through_infra_not_the_cluster(self):
        jobs = self.workflow['jobs']
        notify = jobs['notify-infra']
        self.assertEqual(notify['uses'], './.github/workflows/notify-infra.yaml')
        self.assertEqual(notify['with']['tap-template'], '${{ inputs.tap-template-name }}')
        self.assertIn("github.ref == format('refs/heads/{0}', inputs.development-branch)", notify['if'])
        self.assertIn("github.event_name == 'push'", notify['if'])
        build = {s['name']: s for s in jobs['build']['steps']}
        self.assertIn("vars.AWS_INFRA_DISPATCH_ROLE == ''", build['Require infra dispatch for GitOps tap releases']['if'])
        self.assertEqual(jobs['build']['outputs']['image'], '${{ steps.published-image.outputs.image }}')
        # Schemas are published from integrations after the release PR merges, never by the build.
        for job in ['integration-schema-generate-development', 'integration-schema-generate-production',
                    'integration-schema-generate-environment']:
            self.assertIn('!inputs.tap-template-name', jobs[job]['if'])
        for job in ['deploy-development', 'deploy-production', 'deploy-environment']:
            steps = {s['name']: s for s in jobs[job]['steps']}
            self.assertIn('!inputs.tap-template-name', steps['Deploy tap container with job-template']['if'])
            self.assertNotIn('integrations-token', json.dumps(jobs[job]))
        for job in ['deploy-development', 'deploy-production']:
            self.assertIn('!inputs.environment', jobs[job]['if'])

if __name__ == '__main__':
    unittest.main()
