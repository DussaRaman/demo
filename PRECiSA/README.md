PRECiSA (Program Round-off Error Certifier via Static Analysis)
==

[PRECiSA](https://shemesh.larc.nasa.gov/fm/PRECiSA) accepts as input functional expressions written in PVS format, e.g., [`cd2d_tau_double.pvs`](CD2D_tau/cd2d_tau_double.pvs) and generates a certificate of the round-off floating-point error in the form of a PVS theory and its proofs, e.g., [`cert_cd2d_tau_double.pvs`](CD2D_tau/cert_cd2d_tau_double.pvs). This certificate can be used to compute concrete error bounds, which are probably correct, e.g.,
[`clgen_cd2d_tau_double.pvs`](CD2D_tau/clgen_cd2d_tau_double.pvs).

The PVS utility `proveit` can be used to verify the PVS certificates:

```
$ proveit -sc CD2D_tau/clgen_cd2d_tau_double.pvs
```

The output to that command is:

```
Removing CD2D_tau/.pvscontext CD2D_tau/pvsbin/ CD2D_tau/cert_cd2d_tau_double.summary 
Processing CD2D_tau/cert_cd2d_tau_double.pvs. Writing output to file CD2D_tau/cert_cd2d_tau_double.summary
Proof summary for theory cert_cd2d_tau_double
    Theory totals: 24 formulas, 24 attempted, 24 succeeded (272.69 s)
Grand Totals: 24 proofs, 24 attempted, 24 succeeded (272.69 s)
```



