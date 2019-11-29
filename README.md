# openebs-repare-script
The aim of this script is to repare openebs when 2 of 3 vm and disks have been deleted and new disk have been installed.
It put the CSR in Init phase, remove the old replica id from the cstorVolume and let openebs create and rebuild new.
