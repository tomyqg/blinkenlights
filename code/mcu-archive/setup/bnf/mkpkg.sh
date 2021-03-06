#!/bin/sh

for n in $(seq 1 20); do
	dir="23.23.23.$n"
	echo -n "Packing update file for $dir..."
	cd $dir
	tar -f /var/www/update-$dir.tar -c *
	cd ..
	echo "done."
done

echo -n "Packing generic update file for all MCUs..."
cd update
tar -f /var/www/update.tar -c *
echo "done."
