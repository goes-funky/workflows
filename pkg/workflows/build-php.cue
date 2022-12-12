package workflows

import "github.com/goes-funky/workflows/pkg/common"

common.#workflow & {
    name: "PHP Linting & Testing"

    on: workflow_call: {
        inputs: {
            database: {
                required:    false
                default:     "none"
                type:        "string"
                description: "Database engine to use for tests (mysql and postgres are supported)"
            }
            extensions: {
                type:        "string"
                description: "Comma-separated string of php extensions"
            }
            "skip-migrate": {
                type:        "boolean"
                description: "Whether to skip php artisan migrate"
                default:     false
            }
            "skip-duplicate-actions-on-manual-runs": {
                type:        "boolean"
                description: "Whether to skip duplicate actions on manual workflow runs"
                default:     true
            }
        }
        secrets: "ssh-private-key": {
            description: "SSH private key used to authenticate to GitHub with, in order to fetch private dependencies"
            required:    true
        }
    }
    jobs: {
        "check-pr": {
            if: "${{ github.event_name == 'pull_request' || github.event_name == 'pull_request_target' }}"
            steps: [{
                uses: "amannn/action-semantic-pull-request@v4"
                env: GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
            }]
        }
        matrix: {
            needs: ["check-pr"]
            if: "${{ always() && (needs.check-pr.result == 'success' || needs.check-pr.result == 'skipped') }}"
            outputs: matrix: "${{ steps.set-matrix.outputs.matrix }}"
            steps: [{
                id: "set-matrix"
                run: """
                    echo \"matrix={\\\"php-version\\\":[\\\"8.1\\\"],\\\"extensions\\\":[\\\"${{ inputs.extensions }}\\\"],\\\"database\\\":[\\\"${{ inputs.database }}\\\"]}\" >> "$GITHUB_OUTPUT"
                    """
            }]
        }

        prepare: {
            needs: ["matrix"]
            if:        "${{ always() && needs.matrix.result == 'success' }}"
            strategy: {
                "fail-fast": true
                matrix:      "${{fromJson(needs.matrix.outputs.matrix)}}"
            }
            env: key: "cache-v1-${{ matrix.php-versions }}-${{ matrix.extensions }}"
            steps: [{
                uses: "actions/checkout@v3"
                name: "Checkout"
            }, {
                uses: "dkhunt27/action-conventional-commits@master"
                with: "github-token": "${{ secrets.GITHUB_TOKEN }}"
                if: "github.ref != 'refs/heads/${{ github.event.repository.default_branch }}'"
            }, {
                name: "Setup cache environment"
                id:   "extcache"
                uses: "shivammathur/cache-extensions@v1"
                with: {
                    "php-version": "${{ matrix.php-version }}"
                    extensions:    "${{ matrix.extensions }}"
                    key:           "${{ env.key }}"
                }
            }, {
                name: "Cache extensions"
                uses: "actions/cache@v3"
                with: {
                    path:           "${{ steps.extcache.outputs.dir }}"
                    key:            "${{ steps.extcache.outputs.key }}"
                    "restore-keys": "${{ steps.extcache.outputs.key }}"
                }
            }, {
                name: "Setup PHP"
                uses: "shivammathur/setup-php@v2"
                with: {
                    "php-version": "${{ matrix.php-version }}"
                    coverage:      "xdebug"
                    tools:         "php-cs-fixer"
                    extensions:    "${{ matrix.extensions }}"
                }
            }, {
                name: "Setup SSH Agent"
                uses: "webfactory/ssh-agent@v0.7.0"
                with: "ssh-private-key": "${{ secrets.ssh-private-key }}"
            }, {
                name: "Validate composer.json and composer.lock"
                run:  "composer validate"
            }, {
                name: "Cache Composer packages"
                id:   "composer-cache"
                uses: "actions/cache@v3"
                with: {
                    path: "vendor"
                    key:  "${{ runner.os }}-php-${{ hashFiles('**/composer.lock') }}"
                    "restore-keys": """
                        ${{ runner.os }}-php-

                        """
                }
            }, {
                name: "Install dependencies"
                if:   "steps.composer-cache.outputs.cache-hit != 'true'"
                run:  "composer install --prefer-dist --no-progress --no-suggest"
            }]
        }

        check: {
            needs: ["matrix", "prepare"]
            if:        "${{ always() && needs.prepare.result == 'success' }}"
            strategy: {
                "fail-fast": true
                matrix:      "${{fromJson(needs.matrix.outputs.matrix)}}"
            }
            env: key: "cache-v1-${{ matrix.php-versions }}-${{ matrix.extensions }}"
            steps: [{
                uses: "actions/checkout@v3"
                name: "Checkout"
            }, {
                name: "Setup cache environment"
                id:   "extcache"
                uses: "shivammathur/cache-extensions@v1"
                with: {
                    "php-version": "${{ matrix.php-version }}"
                    extensions:    "${{ matrix.extensions }}"
                    key:           "${{ env.key }}"
                }
            }, {
                name: "Cache extensions"
                uses: "actions/cache@v3"
                with: {
                    path:           "${{ steps.extcache.outputs.dir }}"
                    key:            "${{ steps.extcache.outputs.key }}"
                    "restore-keys": "${{ steps.extcache.outputs.key }}"
                }
            }, {
                name: "Setup PHP"
                uses: "shivammathur/setup-php@v2"
                with: {
                    "php-version": "${{ matrix.php-version }}"
                    extensions:    "${{ matrix.extensions }}"
                }
            }, {
                name: "Composer packages from cache"
                id:   "restore-composer-cache"
                uses: "actions/cache@v3"
                with: {
                    path: "vendor"
                    key:  "${{ runner.os }}-php-${{ hashFiles('**/composer.lock') }}"
                    "restore-keys": """
                        ${{ runner.os }}-php-

                        """
                }
            }, {
                name: "PHPStan cache"
                uses: "actions/cache@v3"
                with: {
                    path: "/tmp/phpstan"
                    key:  "${{ runner.os }}-phpstan-${{ github.sha }}"
                    "restore-keys": """
                        ${{ runner.os }}-phpstan-${{ github.sha }}
                        ${{ runner.os }}-phpstan
                        """
                }
            }, {
                name: "Psalm cache"
                uses: "actions/cache@v3"
                with: {
                    path: "~/.cache/psalm"
                    key:  "${{ runner.os }}-psalm-${{ github.sha }}"
                    "restore-keys": """
                        ${{ runner.os }}-psalm-${{ github.sha }}
                        ${{ runner.os }}-psalm
                        """
                }
            }, {
                name: "Changed PHP files"
                id:   "changed-php-files"
                uses: "tj-actions/changed-files@v34"
                with: files: """
                    **/*.php

                    """
            }, {
                name: "Check Style"
                run:  "vendor/bin/php-cs-fixer fix --config=devconf/.php-cs-fixer.php --path-mode=intersection --dry-run --stop-on-violation --diff --using-cache=no --allow-risky yes -vvv ${{ steps.changed-php-files.outputs.all_changed_files }}"
            }, {
                name: "Run Phpstan"
                run:  "vendor/bin/phpstan analyse -c devconf/phpstan.neon --error-format=github"
            }, {
                name: "Run Psalm"
                run:  "vendor/bin/psalm --config=devconf/psalm.xml --output-format=github --use-baseline=psalm-baseline.xml"
            }]
        }
        test: {
            needs: ["matrix", "prepare"]
            if:        "${{ always() && needs.prepare.result == 'success' }}"
            strategy: {
                "fail-fast": true
                matrix:      "${{fromJson(needs.matrix.outputs.matrix)}}"
            }
            env: {
                APP_ENV: "testing"
                key:     "cache-v1-${{ matrix.php-versions }}-${{ matrix.extensions }}"
            }
            steps: [{
                uses: "actions/checkout@v3"
                name: "Checkout"
            }, {
                name: "Setup cache environment"
                id:   "extcache"
                uses: "shivammathur/cache-extensions@v1"
                with: {
                    "php-version": "${{ matrix.php-version }}"
                    extensions:    "${{ matrix.extensions }}"
                    key:           "${{ env.key }}"
                }
            }, {
                name: "Cache extensions"
                uses: "actions/cache@v3"
                with: {
                    path:           "${{ steps.extcache.outputs.dir }}"
                    key:            "${{ steps.extcache.outputs.key }}"
                    "restore-keys": "${{ steps.extcache.outputs.key }}"
                }
            }, {
                name: "Setup PHP"
                uses: "shivammathur/setup-php@v2"
                with: {
                    "php-version": "${{ matrix.php-version }}"
                    coverage:      "xdebug"
                    tools:         "php-cs-fixer"
                    extensions:    "${{ matrix.extensions }}"
                }
            }, {
                name: "Composer packages from cache"
                id:   "restore-composer-cache"
                uses: "actions/cache@v3"
                with: {
                    path: "vendor"
                    key:  "${{ runner.os }}-php-${{ hashFiles('**/composer.lock') }}"
                    "restore-keys": """
                        ${{ runner.os }}-php-

                        """
                }
            }, {
                name: "Set environmental variables"
                if:   "${{ matrix.database == 'pgsql' }}"
                run: """
                    echo \"DB_DSN=postgres://$USER@127.0.0.1/testdb?sslmode=disable&max_conns=20&max_idle_conns=4\" >> \"$GITHUB_ENV\"

                    """
            }, {
                uses: "ankane/setup-postgres@v1"
                if:   "${{ matrix.database == 'pgsql' }}"
                with: database: "testdb"
            }, {
                name: "Set environmental variables"
                if:   "${{ matrix.database == 'mysql' }}"
                run: """
                    echo \"DB_DSN=mysql://$USER:@127.0.0.1:3306/testdb\" >> \"$GITHUB_ENV\"
                    echo \"DB_CONNECTION=mysql\" >> \"$GITHUB_ENV\"

                    """
            }, {
                uses: "ankane/setup-mysql@v1"
                if:   "${{ matrix.database == 'mysql' }}"
                with: database: "testdb"
            }, {
                name: "Migrate DB"
                if:   "!inputs.skip-migrate"
                run:  "php artisan migrate"
            }, {
                name: "Run Phpunit"
                run:  "vendor/bin/phpunit"
            }]
        }
    }
}
