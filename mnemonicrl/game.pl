#!/usr/bin/perl

use strict;
use warnings;
use lib "../perlrl";
use lib "..";
use lib "../PUtil/bundle";
use Util;

use PerlRL::Server;

GAME->init(shift(@ARGV) // "MnemonicRL.game");
GAME->start;
