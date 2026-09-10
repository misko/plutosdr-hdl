# Offline C1 actual-run admission evidence

No vendor simulation or physical run is included. Source FWf5c488dda /
HDLae364af2e; reviewed CDC runtime02de07cc is unchanged. Final original test
handle55700 exited0:101PASS16.22s. Earlier97287 failed two X/Z command-line
driver cases (38PASS/2FAIL);62222 passed61. Original failures remain intact.

`prepared/` is the full48-member C1 run freeze, inventory
`9c81c43d9ed0bbc6cfba1d40074d11ec8cd94530fc9d7920de809bd6d68ce39c`.
Only candidate C is added; the old dec20 R1/D0/S0 reference and original
stimulus/observation/CSV/extra-edge contracts are unchanged. Qualified status
does not mean raw217 equality. New scalar CDC observer is additional.

`source/` records the new code and local test import dependencies;
`attempts/` retains the original failed source/log and subsequent logs;
`cases/` retains bounded final-case inputs and logs. Generated VVP binaries and
the large derivative historical parser-only log are intentionally excluded,
still locally retained. No actual C1 result may be inferred from compile-only
hierarchy, quiescent runtime fixture, or synthetic receipt parser tests.

All manifest members and SHA256SUMS must be explicitly Git-added even if a
global ignore matches. The separate read-only Git-object verifier must prove
tracked paths exactly equal manifest members plus SHA256SUMS after commit.
