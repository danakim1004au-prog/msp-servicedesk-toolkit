# Runbook — Workshop PC Run-Up (SOE Build)

End-to-end procedure for building a new machine to standard and shipping
it to a client site. Automated steps use `Invoke-SdPcRunUp`; the rest is
bench discipline.

## Before you image

1. **Unbox and inspect.** Note any transit damage on the ticket with
   photos before powering on — warranty conversations go better with
   evidence.
2. **Record serial and asset details** in the PSA against the client's
   configuration/asset board.
3. **Firmware first.** Enter UEFI: confirm TPM 2.0 enabled, Secure Boot
   on, boot order sane, and update the firmware if the vendor has a
   current release. Doing this after Windows is set up doubles the work.

## Imaging / provisioning

Pick the path that matches the client:

- **Intune + Autopilot clients:** upload the hardware hash, assign the
  deployment profile, and let Autopilot do the heavy lifting. The run-up
  script then only handles the workshop QA steps.
- **Golden image clients:** apply the client's image via USB/PXE, then run
  the full run-up.
- **One-off/BYO:** clean Windows install from current media, then full
  run-up.

## The run-up

On the machine, from an elevated PowerShell:

```powershell
Import-Module ./SdKit/SdKit.psd1

# Dry run first — check the computed name and steps before touching anything.
Invoke-SdPcRunUp -BaselinePath ./config/runup-baseline.json `
                 -ConfigPath ./config/clients.json `
                 -ClientCode ACME -DeviceType LT -WhatIf

# Looks right? Run it for real.
Invoke-SdPcRunUp -BaselinePath ./config/runup-baseline.json `
                 -ConfigPath ./config/clients.json `
                 -ClientCode ACME -DeviceType LT -ReportPath ./reports
```

The run covers: rename to convention, time zone, power plan, standard app
set (winget), debloat, file-extension visibility, TPM/BitLocker/disk QA,
and flags Windows Update as the finishing pass.

## After the script

1. **Windows Update to exhaustion.** Fresh images usually need 2–3
   passes. Restart between passes.
2. **BitLocker.** Confirm protection is on and the recovery key is
   escrowed (Entra ID for Intune clients; documented per client standard
   otherwise). The run-up report will have flagged this.
3. **Sign-in test.** Log on as a test/standard user, open Outlook, Teams
   and the client's line-of-business app. "It boots" is not QA.
4. **Attach the run-up report** (`runup-<NAME>-<date>.md`) to the ticket.
5. **Update the asset record** with the final computer name.

## Shipping checklist

- [ ] Run-up report attached, zero unexplained Failed steps
- [ ] BitLocker on, key escrowed
- [ ] Charger/dock/peripherals in the box
- [ ] Asset record updated (name, serial, user, site)
- [ ] Ticket updated with delivery/installation arrangements

If the machine is being swapped for an old one, book the data migration
and old-device wipe as their own ticket tasks — they get missed when they
ride along inside a run-up ticket.
