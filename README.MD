The Field Groups is a Bugzilla extension that adds optgroup ability to bug fields
## Installation
* Download the latest release.
* Unpack the download. This will create a directory called "FieldGroups".
* Move the "FieldGroups" directory into the "extensions" directory in your Bugzilla installation.
Go to your Bugzilla directory
Apply the patch and run checksetup.pl
```
patch -p0 -i extensions/FieldGroups/patch-4.1.diff
./checksetup.pl
```
