#############
# Roguelike #
#############

package Roguelike;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

# Pass along all the Utility routines to the program.
use Exporter ();
our @ISA = ("Exporter");
our @EXPORT = do {
  no strict "refs";
  grep defined &$_, keys %{ __PACKAGE__ . "::" }
};
push @EXPORT, '$Game', '$Player';

BEGIN {
  use Roguelike::Engine;
  # See here! Perl will load up the templates before it creates Game!
  $Game = new Roguelike::Engine;
}

# Load the Standard Library.

use Roguelike::StdLib;

# Export them.
no strict "refs";
while (my ($name, $obj) = each(%{ $Game->{Templates} })) {
  my $var = "Roguelike::$name";
  $$var = $obj;
  push @EXPORT, "\$$name";
}
use strict "refs";

42;
