#!/usr/bin/perl

# Back to plaintext so I can do more vim magic

use strict;
use warnings;
use lib "../../";
use lib "../../perlrl";

use BDSM::Map;

die "Usage: map\n" unless @ARGV;

my $map = BDSM::Map->new(shift @ARGV);
$map->_dump(*STDOUT);
