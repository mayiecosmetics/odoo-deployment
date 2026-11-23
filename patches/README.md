# Security hotfixes on top of the core

One file per advisory, `NNNN-<advisory>-<short-name>.patch`, applied by the
`Dockerfile` at image build with `patch -p1 -N -d /usr/lib/python3/dist-packages`.
Each file starts with a header that names the advisory, the upstream commits it
carries and the first core build that already contains them.

The directory may hold no patch at all. This file keeps it in git, because the
`Dockerfile` copies it. See "Security hotfixes" in `../README.md` for the rules
and for the list of patches carried so far.
