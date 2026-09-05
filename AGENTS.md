
<!-- floppy:agents-section -->
## Agent memory

This repository uses the `floppy` plugin for its session ritual and its
durable memory. The entry point is `.floppy/run` — see `agent-memory`
for what a note looks like and how the memory is laid out, and
`start` / `workstatus` / `wrap` for the three rites
built on top of it. Settings live in `.floppy/config`; the memory itself is
under `.agent-memory`.
