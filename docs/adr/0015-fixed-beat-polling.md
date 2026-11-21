# 0015. Polling runs on fixed beats

Status: Accepted

## Context
A loop that sleeps an interval after each run drifts by the run's duration, and a Mac waking from
sleep would fire every missed beat at once.

## Decision
Background upload polling fixes its beats when it starts (start plus one interval, plus two, and
so on). A slow run or late start never shifts them, and a loop more than an interval behind skips
the missed beats.

Code: `BackgroundUploadEvents`.
