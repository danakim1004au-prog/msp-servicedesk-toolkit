# Runbook — "The Internet Is Down" Network Triage

The most common phone call an MSP desk takes, and the easiest to fumble by
jumping straight to the modem. Work up the stack; `Test-SdNetworkStack`
automates the ladder.

## On the phone, before any tools

1. **Scope it.** One person or the whole office? One app or everything?
   One user + one app usually isn't the network at all.
2. **What changed?** New desk, new cable, storm last night, electrician
   in this morning — the answer is in there more often than not.
3. **Get eyes on the kit.** Lights on the switch/router? Anything
   unplugged? The client is your remote hands; talk them through it in
   plain English.

## The ladder

```powershell
Import-Module ./SdKit/SdKit.psd1

# On the affected machine (locally or via RMM remote shell):
Test-SdNetworkStack -InternalHost acme-dc01.acme.local -AsTicketNote
```

| Layer | Check | If it fails, think |
|---|---|---|
| 1 | Adapter up | Cable, Wi-Fi, dock, disabled NIC |
| 2 | Real IP vs APIPA (169.254.x.x) | DHCP server down/exhausted, switch port, VLAN |
| 3 | Gateway ping | Local router/firewall — problem is inside the building |
| 4 | DNS (internal + external) | DC/DNS server down; ISP DNS; conditional forwarders |
| 5 | HTTPS egress | ISP outage, firewall rule, content filter |
| 6 | M365 endpoints | Firewall/SSL inspection eating Microsoft traffic |
| 7 | VPN state | Full-tunnel VPN steering traffic and DNS somewhere slow |

The first failing layer is where you work. Everything above it failing is
usually a symptom, not a second problem.

## Patterns worth knowing

- **APIPA everywhere in the office** → DHCP. Check the server/router
  providing leases before anything else.
- **Internal DNS fails, external works** → the DC is unhappy. Expect
  logins, shares and printers to be broken too; that's one ticket, not four.
- **Everything resolves, nothing loads** → egress. Ring the ISP with the
  service number ready, and check the firewall hasn't updated overnight.
- **Only M365 is broken** → check the Service Health dashboard *and* the
  firewall's SSL inspection before blaming Microsoft. Layer 6 catching
  what layer 5 passes points at the filter.
- **"It's slow" not "it's down"** → different runbook: start with
  `Invoke-SdTriage` on the affected machine (disk space and uptime settle
  half of these), then look at link saturation.

## Escalate when

- The fix lives in firewall/switch config you don't have change rights to
- A site-wide outage passes the 30-minute mark without a clear cause
- The ISP confirms a fault — hand to the service coordinator to run the
  client comms while you monitor

Escalate with the ladder output in the ticket (`-AsTicketNote`) — the
first failing layer is exactly what the engineer wants to know.
