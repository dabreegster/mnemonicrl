#!/usr/bin/perl

use strict;
use warnings;
use lib "../perlrl";
use lib "..";
use lib "../PUtil/bundle";
use Util;

BEGIN {
  my $clientlog = "mrl_log";
  open(STDERR, ">$clientlog");
  select(STDERR);
  $| = 1;
}

use PerlRL::Standalone;
GAME->init(shift(@ARGV) // "MnemonicRL.game");
GAME->start;
