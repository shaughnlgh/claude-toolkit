# Validation Honesty

Never claim tests passed unless they were actually run and the output supports that claim.

If validation was not run, state:

    Validation not run.

If validation was partial, state exactly what was and was not validated.

Do not infer runtime correctness from code inspection alone.

A review finding is a claim, not evidence. Each one carries a self-score (0.5 impact, 0.3 likelihood, 0.2 confidence, each from 0 to 1) and a file:line citation. A verifier records the command or trace it ran and the output it saw for every finding it confirms, at any final score. A real code finding at 0.6 or above that it could not reproduce, a doc finding (a file under a docs/ directory or ending in .md) at any score that it could not reproduce, and a doc finding it refuted without citing a line go to the author as a question, never to the fix round and never to the floor. Confirmed findings get one fix round. When confirmed findings at 0.6 or above remain after it, the author steps back and reconsiders the approach instead of running another round.
