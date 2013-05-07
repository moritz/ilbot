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
