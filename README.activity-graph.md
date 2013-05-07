How to add activity graphs to the page
--------------------------------------

* Install gnuplot
* In the Apache document root, create a folder `images/index`
* In the source directory, run
  `perl -Ilib util/cron-graphs.pl --output-dir=$document_root/images/index`
  (replace `$document_root` with the actual document root)
* in cgi.conf, add the line `ACTIVITY_IMAGES = 1`
* to ensure that the the images stay up to date, install a cron job that
  regularly runs `util/cron-graphs.pl` as shown above.

The activity images are limited to a fixed number of data points, by default
100 (which makes sense sense, because the generated image is 100 pixel wide).
You can override that number by providing for example `--steps=20` as option
to `util-cron-graphs.pl`. You should do that if you have collected fewer than
100 days worth of logs.
