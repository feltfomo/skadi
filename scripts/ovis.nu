def control [action: string] {
    ^systemctl --user --no-pager $action ovis.service
    exit $env.LAST_EXIT_CODE
}

def main [] {
    control status
}

def "main on" [] {
    control start
}

def "main off" [] {
    control stop
}

def "main restart" [] {
    control restart
}

def "main status" [] {
    control status
}
