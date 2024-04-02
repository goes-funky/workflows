package common

#workflow: {
    name: string
    on: {
        push?:          #on_push
        pull_request?:  #on_pr
        workflow_call?: #on_wfc
    }
    env?: [string]: string
    jobs: [string]: #job
}

#on_wfc: {
    inputs: [string]: #wfc_input_string | #wfc_input_bool | #wfc_input_number
    secrets: [string]: {
        description: string
        required?:   bool
    }
}

#on_push: {
    branches?: [string]
    paths?: [string]
    tags?: [string]
}

#on_pr: {
    branches?: [string]
    types?: [string]
}

#wfc_input_string: {
    type:        "string"
    description: string
    default?:    string
    required?:   bool
}

#wfc_input_bool: {
    type:        "boolean"
    description: string
    default?:    bool
    required?:   bool
}

#wfc_input_number: {
    type:        "number"
    description: string
    default?:    int
    required?:   bool
}

#job: {
    needs?: [...string]
    if?: string
    env?: [string]: string
    environment?: string
    "runs-on":    string | *"ubuntu-latest"
    name?:         string
    outputs?: [string]: string
    strategy?: {
        "fail-fast"?: bool
        "max-parallel"?: int
        matrix?: #string_map | =~ "^\\$\\{\\{.*\\}\\}$"
    }
    "timeout-minutes": int | *15
    steps: [...#step]
    permissions?: [string]: string
}

#step: {
    name?: string
    if?:   string
    id?:   string
    "continue-on-error"?: bool
    needs?: [...string]
    uses?: string
    with?: [string]: string | bool | int
    env?: [string]:  string
    run?: string
}

#string_map: [string]: [...string]
