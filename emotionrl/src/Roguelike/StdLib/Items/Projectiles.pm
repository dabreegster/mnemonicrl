##############################
# StdLib::Items::Projectiles #
##############################

package Roguelike::StdLib::Items::Projectiles;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

my $projectile = $Game->{Templates}{Obj}->new(Category => "Projectiles", Symbol => ")");

define(Projectile => $projectile, []);

42;
