# Proof of concept for building Corda projects inside a Docker container

This projects shows how keep a complete build environment for Corda as a Docker image and how to build the project
using this image.

## Table of Contents

- [Before you start](#before-you-start)
- [TL;DR](#tldr)
- [References](#references)

_(TOC generated by [markdown-toc](https://github.com/jonschlinkert/markdown-toc))_

Before you start
----------------

This PoC requires a Docker engine (of course!) and Bash shell. The wrapper scripts expects a `docker` command to be available and it can contact a Docker engine without access rights elevation.

TL;DR
-----

To start a shell inside a [Docker] container, just run the wrapper script:

```bash
./with-docker-container.sh
```

alternatively, to run a command inside a Docker container:

```bash
./with-docker-container.sh
```

References
----------

* [Docker] - The container engine

[Docker]: https://docs.docker.com/ "Docker unlocks the potential of your organization by giving developers and IT the freedom to build, manage and secure business-critical applications without the fear of technology or infrastructure lock-in."
