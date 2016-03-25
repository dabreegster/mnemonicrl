############################
# StdLib::Items::Equipment #
############################

package Roguelike::StdLib::Items::Equipment;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

my $equipment = $Game->{Templates}{Obj}->new(
  Power => "1d1",
  Mod => 0,
  MaxMod => 0,
  Init => sub {
    my $self = shift;
    # No way to tell if an instance or not.
    # Hrm. Durability.
    $self->{Use} = $self->g("Durability");
  },
  # Doesn't overwrite; g() rules! But UTIL_rating would apply to all.
  Routines => {
    rating => sub {
      my $self = shift;
      my $use = int( ( 100 * $self->g("Use") ) / $self->g("Durability") );
      # Wow.
      return int( ($use * roll($self->g("Power")) + $self->g("Mod")) / 100 );
    },
    diminish => sub {
      my $self = shift;
      return if $self->g("Use") == 0;
      $self->{Use}--;
      if ($self->g("Use") < 1) {
        # Broken! What type of message? Are we in inventory or on a tile?
        # For now, we dunno. :(
        $self->msg("[subj] has broken!");
      }
      return 1;
    }
  },
  Use => 1,
  Durability => 1,
);

my $weapon = $equipment->new(
  Category => "Weapons",
  Fits => ["Weapon"],
  Wieldable => 1,
);
my $armour = $equipment->new(
  Fits => ["Armour"],
  Category => "Armour",
  Wearable => 1,
);
# Full-body equipment is a bit unique, since it can be Inner or Outer.
my $helmet = $armour->new(Fits => ["Helmet"]);
my $gloves = $armour->new(Fits => ["Gloves"]);
my $amulet = $armour->new(Fits => ["Amulet"]);
my $ring   = $armour->new(Fits => ["LeftRing", "RightRing"]);
my $boots  = $armour->new(Fits => ["Boots"]);

define(Equipment => $equipment, []);
define(Weapon => $weapon, []);
define(Armour => $armour, []);
define(Helmet => $helmet, []);
define(Gloves => $gloves, []);
define(Amulet => $amulet, []);
define(Ring   => $ring,   []);
define(Boots  => $boots,  []);

42;
