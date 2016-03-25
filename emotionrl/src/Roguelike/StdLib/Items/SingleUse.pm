############################
# StdLib::Items::SingleUse #
############################

package Roguelike::StdLib::Items::SingleUse;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

my $item = $Game->{Templates}{Obj}->new();
my $food = $item->new(Category => "Food", Sustenance => 0, Edible => 1);
my $scroll = $item->new(Category => "Scrolls", Readable => 1);
my $potion = $item->new(Category => "Potions", Drinkable => 1);

define(DisposableItem => $item, []);
define(Food => $food, []);
define(Scroll => $scroll, []);
define(Potion => $potion, []);

42;
