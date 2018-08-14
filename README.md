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


The configuration options are (note that currently calling with `=`
doesn't work):

- `-m '.'` or `--mnt '.'`: A *space-separated* list of directories to
  mount within the container.  The default is `.` which is expanded to
  the current directory.  Relative directory names are allowed
  (expanded using `realpath`).  If prefixed with `ro:`, bind-mount it
  read-only.  The defaults (which are always included... you don't
  need to also specify these) include `/bin`, `/usr`, `/lib`, `/proc`,
  `/dev/urandom`.

- `-v`: Be more verbose in execution (uses `set -x`).
  execution.

- `-b DIR`:  The temporary directory used to assemble our
  isolated environment..  Defaults to `mktemp -d isolate.XXXXXXXX`,
  which is an `isolate.*` directory in the system-default tmpdir.  If
  you specify this yourself, you are responsible for cleaning it up
  when done.

- `--no-net`: Don't unshare the network namespace.  This is needed so
  that Jupyter kernels can communicate via loopback.

- `--`.  Separate options to `isolate.sh` from program to run.  All
  options to `isolate.sh` must be before program to run.


Use with Jupyter kernels
========================

This was first made to isolate Jupyter kernels when using `nbgrader`.
While no means the only purpose, it is documented here to get started.

Jupyter kernels are created via *kernelspecs*, as seen in
[the spec itself](https://jupyter-client.readthedocs.io/en/stable/kernels.html#kernel-specs).
To make an isolated kernel, you would make a (for example)
`python3-isolated/kernel.json` file in
`~/.local/share/jupyter/kernels` (recommendation: take existing kernel
dir, copy, and modify it) and edit it as below.  Only `argv` needs to
be modified (`isolate.sh` and other arguments prepended):

```
{
  "argv": [
    "isolate.sh", "--mnt", "{connection_file} .", "--no-net", "--",
    "/usr/bin/python3",
    "-m",
    "ipykernel",
    "-f",
    "{connection_file}"
  ],
  "display_name": "Python 3 (os) isolated",
  "language": "python"
}
```

You will need to adjust the `--mnt` option to handle whatever you need
to run your notebooks.  The defaults are enough to run system Python,
but you should add any `conda` directories.

Then, when you run `nbgrader autograde`, use the
`--ExecutePreprocessor.kernel_name=python3-isolated` option and it
will run using this kernel.

nbgrader details
----------------

* Create a conda environment to match what you use in your course (it
  would be better to directly use the existing container, but the
  point of this script is to not have the overhead of setting this
  up).

* Activate that conda environment.  Install jupyter, nbgrader, and
  whatever else is needed.

* Mount the course directory on your computer somehow.

* `cd` to the root of the course directory.  (i.e. the directory under
  which there are the `source`, `release`, `autograded`,
  etc. directories).

* `umask 007` - make sure that files you make will be group
  writeable.  (groupshared only)

* `pip install --upgrade --no-deps
  https://github.com/rkdarst/nbgrader/archive/live.zip` - we still
  need to install custom nbgrader to make files group shared.
  (groupshared only)

* Create a nbgrader config file within the root of the course
  directory (what you have mounted) with these lines (groupshared
  only):

      c = get_config()
      c.BaseConverter.groupshared = True

* Create a new Python kernel (run this with the interpreter you want
  to use): `python -m ipykernel install
  --sys-prefix --name=python3-isolated` (output shows: *Installed
  kernelspec python3-isolated in
  /.../conda/share/jupyter/kernels/python3-isolated`*)

* Edit `kernel.json` in that directory to wrap the kernel in
  `isolate.sh` and set the relevant options.  You need to set at least
  `['-m', 'dir1 dir2 {connection_file} .', '--no-net' ,'--',` at the start.

  A full example:

      {
       "argv": [
           "isolate.sh",
           "--mnt", "/work/modules/ /l/darstr1/conda {connection_file} .",
           "--no-net", "--",
           "/l/darstr1/conda/bin/python",
           "-m",
           "ipykernel_launcher",
           "-f",
           "{connection_file}"
         ],
       "display_name": "python3-isolated",
       "language": "python"
      }

  The `/work/modules` and `/l/darstr1/conda` directories are there
  because those are the paths to my conda base and conda environment.


* Run the autograding using
  `--ExecutePreprocessor.kernel_name=python3-isolated`.  Full example: `nbgrader
  autograde $assignmentname [--student=$name]
  --ExecutePreprocessor.kernel_name=python3-isolated`




Problems
========

- Security is not fully checked.  The chroot can possibly be escaped
  from, and some container/namespace/chroot guru could check and
  improve things.

- Probably only works with bash.

- You appear to be root inside the isolated environment, but you are
  *not*: it just looks like it but to any observer outside, you are you
  former user.  Document this or maybe make it su inside again.

- This does not work within a container - as in, recursive containers
  don't work.  Yet?

- `realpath` can't expand `~` in phase 2, because once in the env
  the user info isn't know.

- `realpath` expands symbolic locations to physical locations.  This
  can cause problems when the programs expect the symbolic locations.
  To get around this, `realpath` is only used for non-absolute paths.
  If this becomes a problem, specify full paths starting with `/`.
