# Base files of the official Odoo image

`entrypoint.sh`, `wait-for-psql.py` and `odoo.conf` are copied unchanged from
[odoo/docker](https://github.com/odoo/docker), directory `19.0/`, commit
`0ea197eb3852ca500e38fd72074b314833ee7dc8` (release 20261112). Their git blob
hashes are the same as upstream, and they are byte-identical to the files in
`odoo:19.0-20261112`.

They are used only by the `odoo-core` stage of `../../Dockerfile`, which builds
the core from a nightly package while Docker Hub has no tag new enough. Delete
this directory together with that stage when the `Dockerfile` goes back to
`FROM odoo:19.0-<date>`.
