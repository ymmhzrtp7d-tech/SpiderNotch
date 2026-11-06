#!/usr/bin/perl
#
# SpiderNotch: starts the "Now Playing" helper.
#
# macOS only lets Apple's own programs read the system Now Playing information,
# so SpiderNotch runs its small helper (SpiderNotchMedia.dylib) inside Apple's
# /usr/bin/perl. This script just loads the helper and hands over to it.
# See SpiderNotchMedia.m for what the helper does.
#
# Usage: /usr/bin/perl now-playing.pl /full/path/to/SpiderNotchMedia.dylib

use strict;
use warnings;
use DynaLoader;

my $library = $ARGV[0] // '';
die "Usage: now-playing.pl /path/to/SpiderNotchMedia.dylib\n" unless -f $library;

my $handle = DynaLoader::dl_load_file($library, 0)
    or die "Couldn't load the helper: " . (DynaLoader::dl_error() // 'unknown error') . "\n";
my $entry = DynaLoader::dl_find_symbol($handle, 'spidernotch_media_main')
    or die "The helper has no entry point.\n";
DynaLoader::dl_install_xsub('main::spidernotch_media_main', $entry);
spidernotch_media_main();
