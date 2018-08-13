Namespace isolation script
==========================

This script (`isolate.sh`) uses Linux namespaces to isolate a process
from the rest of the filesystem.  It is similar in effect to `chroot`,
but automates the setup and by using namespaces, can be done by an
unprivledged user.  The usage of the script can be as a wrapper, for
example instead of `python code.py`, one can run `isolate.sh python
code.py`.  You choose which directories to make available inside of
the isolated environment.  For example, you can run `MNTDIRS="."
isolate.sh python` to run a Python process that only has access to `.`
and system Python stuff - not the rest of your home directory.

You may think "isn't this what containers do?" and you would be right.
In fact, in the ideal case this would be a primitive reimplementation
of containers.  However, this is standalone, requires no other system
stuff installed, and is designed to isolate your existing system by
only mounting requested directories, not a different image.  There
*should* be a script like this that already exists - if anyone can
find it, please let me know.

This is alpha stage software.

Usage
=====

There are two primary invocation methods:

- `isolate.sh`: run a `$SHELL` shell within the isolated environment.

- `isolate.sh prog [arg] ...`: Run `prog` with arguments `arg` within
  the environment.


Currently all configuration is done by environment variables - you
can't configure things by the command line.  So, for example, to
change `MNTDIRS` you could run `MNTDIRS='/home/pymod .' isolate.sh
python code.py`.  The environment variables are:

- `MNTDIRS='.'`: A space-separated list of directories to mount within
  the container.  The default is `.` which is expanded to the current
  directory.  Relative directory names are allowed (expanded using
  `realpath`).  If prefixed with `ro:`, bind-mount it read-only.

- `MNTDIRS_BASE="ro:/bin ro:/lib ro:/etc ro:/usr ro:/lib64 ro:/proc"`:
  These are the *default* directories which are always mounted to make
  a functional system.  It is assumed that these don't contain too
  sensitive data - if that is not true, this should be changed.

- `VERBOSE=1`: If set to any value (such as `1`), be more verbose in the
execution.

- `NI_BASEDIR=`.  The temporary directory used to assemble our
  isolated environment..  Defaults to `mktemp -d isolate.XXXXXXXX`,
  which is an `isolate.* directory in the system-default tmpdir.  If
  you specify this yourself, you are responsible for cleaning it up
  yourself.


Use with Jupyter kernels
========================

This was first made to isolate Jupyter kernels when using `nbgrader`.
While no means the only purpose, it is documented here to get started.

Jupyter kernels are created via *kernelspecs*, as seen in
[the spec itself](https://jupyter-client.readthedocs.io/en/stable/kernels.html#kernel-specs).
To make an isolated kernel, you would make a (for example)
`python3-isolated/kernel.json` file in
`~/.local/share/jupyter/kernels` (recommendation: take existing kernel
dir, copy, and modify it) and edit it as below.  Only `argv`
(`isolate.sh` prepended) and `env` (set `MNTDIRS` and whatever options
are needed) are modified:

```
{
  "argv": [
    "isolate.sh"
    "/usr/bin/python3",
    "-m",
    "ipykernel",
    "-f",
    "{connection_file}"
  ],
  "display_name": "Python 3 (os) isolated",
  "language": "python",
  "env": {
    "MNTDIRS": ". ~/path/to/conda"
  }
}
```

You will need to adjust `MNTDIRS` to handle whatever you need to run
your notebooks.  The directory containing `{connection_file}` would
need to be shared - TODO: where is that?

Then, when you run `nbgrader autograde`, use the
`--ExecutePreprocessor.kernel_name=python3-isolated` option and it
will run using this kernel.  TODO: this needs checking!


Problems
========

- Security is not fully checked.  The chroot can possibly be escaped
  from, and some container/namespace/chroot guru could check and
  improve things.

- You shouldn't mount one directory inside of another.

- Currently `/etc` is included in `MNTDIRS_BASE`.  Should this be
  removed?

- Probably only works with bash.

- You appear to be root inside the isolated environment, but you are
  *not*: it just looks like it but to any file outside, you are you
  former user.  Document this or maybe make it su inside again.

- This does not work within a container - as in, recursive containers
  don't work.  Yet?
