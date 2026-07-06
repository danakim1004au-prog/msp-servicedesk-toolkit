# Escalation Guide

Escalating well is a skill, not a failure. A desk where L1s sit on tickets
they can't solve burns clients; a desk where everything bounces straight
to L3 burns engineers. This guide sets the middle path SdKit supports with
`New-SdTicketNote -Escalation`.

## When to escalate

Escalate when **any** of these is true:

- **Time box hit.** 30–45 minutes of genuine troubleshooting on an L1
  ticket without a clear path forward. The time box exists to protect the
  client, not your pride.
- **Blast radius.** The issue affects a whole site, a server, or anything
  where a wrong move makes things worse (storage, backups, firewalls,
  domain controllers).
- **Access ceiling.** The fix needs rights you don't hold (global admin
  actions, firewall changes, hypervisor work). Don't borrow credentials —
  escalate.
- **Repeat offender.** Third ticket for the same symptom on the same
  machine/user. Pattern problems need a root-cause owner, not another
  band-aid.
- **Security smell.** Anything that looks like compromise — odd sign-ins,
  MFA fatigue, mailbox rules the user didn't create — goes up immediately.
  Minutes matter; nobody will criticise a false alarm.

## What a good handover contains

The senior engineer should be able to start where you stopped, not where
you started. `New-SdTicketNote -Escalation` structures this:

1. **Issue and impact** — current state, in one breath.
2. **Steps taken** — numbered, in order, with results.
3. **Ruled out** — the gold. "Not DNS — resolves fine internally and
   externally" saves the next person twenty minutes.
4. **Next steps** — your best theory, even if you're not sure. A wrong
   hypothesis stated clearly is more useful than silence.

## What escalation is not

- **Not a hand-wash.** Stay across the ticket; the client still calls you.
  Ask the engineer what the fix was — that's how L1 becomes L2.
- **Not a queue-jump for noisy clients.** Escalate on severity and
  complexity, not volume of follow-up calls. Note the pressure in the
  ticket and let the service coordinator manage it.
- **Not blame.** A no-blame desk escalates early and often, and the
  post-fix "what was it?" conversation is where the whole team levels up.

## The two-line rule

If you can't summarise the problem and what you've tried in two lines to
the engineer standing at your desk, you're not ready to escalate — you're
ready to re-read your own ticket notes. Tighten them first; half the time
the summary writes the answer.
