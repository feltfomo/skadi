# cava reloads file-backed themes on sigusr1
if (which pkill | is-not-empty) {
  do --ignore-errors { ^pkill -USR1 -x cava }
}
