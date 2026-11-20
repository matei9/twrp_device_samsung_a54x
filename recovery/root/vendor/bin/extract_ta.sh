#!/sbin/sh
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

exec >> /tmp/extract_ta.log 2>&1

vendor_dev=/dev/block/mapper/vendor
while [ ! -e "$vendor_dev" ]; do
  sleep 1
done

vendor_mount=$(mktemp -d /tmp/vendor-ta.XXXXXX) || exit 1
trap 'rmdir "$vendor_mount"' EXIT
if ! mount -t erofs -o ro "$vendor_dev" "$vendor_mount" &&
   ! mount -t ext4 -o ro,noload "$vendor_dev" "$vendor_mount"; then
  echo "Cannot mount the installed vendor partition"
  exit 1
fi
trap 'umount "$vendor_mount" && rmdir "$vendor_mount"' EXIT

model=$(getprop ro.boot.em.model)
# crDroid and other unified builds keep each model's TAs under tee/<model>.
if [ -n "$model" ] && [ -d "$vendor_mount/tee/$model" ]; then
  tee_dir="$vendor_mount/tee/$model"
elif [ -n "$model" ] && [ -d "$vendor_mount/tee_$model" ]; then
  tee_dir="$vendor_mount/tee_$model"
else
  tee_dir="$vendor_mount/tee"
fi

# Crypto Manager driver, ICCC driver, KeyMint TA, TZ_ICCC TA, Gatekeeper TA.
set -- driver/00000000-0000-0000-0000-53626f786476 \
       driver/00000000-0000-0000-0000-494363447256 \
       00000000-0000-0000-0000-4b45594d5354 \
       00000000-0000-0000-0000-0053545354ab \
       00000000-0000-0000-0000-474154454b45

echo "Loading TEE files from $tee_dir (model: $model)"
for file do
  if [ ! -s "$tee_dir/$file" ]; then
    echo "Missing or empty TEE file: $tee_dir/$file"
    exit 1
  fi
done

# init starts services with umask 077; the TEE daemons run as system.
umask 022
mkdir -p /vendor/tee/driver || exit 1
for file do
  cp -p "$tee_dir/$file" "/vendor/tee/$file" || exit 1
done

umount "$vendor_mount" || exit 1
trap 'rmdir "$vendor_mount"' EXIT
setprop crypto.ready 1
