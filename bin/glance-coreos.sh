#!/bin/bash

# download stable channel
aria https://stable.release.core-os.net/amd64-usr/current/coreos_production_openstack_image.img.bz2

# extract image
bunzip2 coreos_production_openstack_image.img.bz2

# Upload to OpenStack
glance image-create --name 'CoreOS' \
  --file coreos_production_openstack_image.img \
  --os-version '1068.10.0' \
  --container-format bare \
  --disk-format qcow2 \
  --visibility public \
  --progress
