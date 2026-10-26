# btop reloads its active theme on sigusr2
if (which pkill | is-not-empty) {
  do --ignore-errors { ^pkill -SIGUSR2 -x btop }
}
