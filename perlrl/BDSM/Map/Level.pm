package BDSM::Map::Level;

use strict;
use warnings;
use Util;

use BDSM::DunGen::Test; # My volatile toy :)
# Standard roguelike stuff
use BDSM::DunGen::Dungeon;
use BDSM::DunGen::Cave;
use BDSM::DunGen::Building;
use BDSM::DunGen::Maze;
# Mnemonic stuff
use BDSM::DunGen::Sky;
use BDSM::DunGen::GuestRoom;
use BDSM::DunGen::Kitchen;

use POSIX ("ceil");

# See to it!
sub addlvl {
  my ($map, $z);
  if (@_ == 2) {
    ($z, $map) = @_;
    $map->{Depth} = $z;
    log_push("Already got map $z ready");
  } else {
    $z = shift;
    if ($z =~ m/^\d+$/) {
      #my $style = "BDSM::DunGen::" . choosernd("Dungeon", "Cave", "Building");
      # TODO: buildings are broken
      my $style = percent(30) ? "Cave" : "Dungeon";
      log_push("Generating a $style for level $z");
      my @size = @{ CFG->{DunGen}{"${style}Size"} };
      $style = "BDSM::DunGen::$style";
      $map = $style->generate(@size);
      $map->{Depth} = $z;
    } else {
      log_push("Loading up map $z");
      $map = BDSM::Map->new($z);
      my $fn = $z;
      $z = $map->{_Data}{Depth} // die "$fn doesnt have Depth set\n";
    }
  }

  # Set up pending stairs, if any
  GAME->{PendingStairs}{$z} //= [];
  $map->stair(-oneway => 1, @$_) foreach @{ delete GAME->{PendingStairs}{$z} };

  GAME->{Levels}{$z} = $map;
  populate($map);
  if ($map->normal) {
    my $linkto = $z == 1 ? "Cyphen" : $z - 1;
    linkstairs($map, GAME->{Levels}{$linkto});
  }
  log_pop;
  return $map;
}

# Link two maps' staircases to each other.
sub linkstairs {
  my ($lower, $upper) = @_;

  # Link the lower to the upper
  my $stair = 0;
  foreach (@{ $lower->{StairsUp} }) {
    $stair = 0 if $stair > $#{ $upper->{StairsDown} };  # Loop through available links
    $lower->stair(-oneway => 1, $_->[1], $_->[2], @{ $upper->{StairsDown}[$stair++] });
  }

  # And the upper to the lower
  $stair = 0;
  foreach (@{ $upper->{StairsDown} }) {
    $stair = 0 if $stair > $#{ $lower->{StairsUp} };  # Loop through available links
    $upper->stair($_->[1], $_->[2], @{ $lower->{StairsUp}[$stair++] });
  }
}

# Populate a map with appropriate stairs, monsters, and items given its depth
sub populate {
  my $map = shift;

  # TODO: more even distribution could happen if we generate hotspots from within each room
  # and store those

  # Generate stairs. Fixed at random(2, 4) for now.
  $map->{StairsUp} = [];
  $map->{StairsDown} = [];
  foreach my $type ("StairsUp", "StairsDown") {
    last if $map->{_Data}{nostairs};
    #foreach (1 .. random(2, 4)) {
    foreach (1 .. 1) {
      my ($y, $x) = $map->getpt;
      $map->mod($y, $x, $type eq "StairsUp" ? "<" : ">");
      push @{ $map->{$type} }, [$map->{Depth}, $y, $x];
    }
  }
  return if $map->{_Data}{empty};

  # Monsters.
  my @baddies;
  foreach my $type (@{ GAME->{Baddies} }) {
    next if $type->Rank == 0; # Never
    #debug "$type->{Type}: chance " . (100 - CFG->{DunGen}{RareMonster} * abs $type->ood($map->{Depth}));
    next unless percent(100 - CFG->{DunGen}{RareMonster} * abs $type->ood($map->{Depth}));
    push @baddies, $type;
  }

  # Items.
  my @stuff;
  foreach my $type (@{ GAME->{Stuff} }) {
    next if $type->Rank == 0;
    next unless percent(100 - CFG->{DunGen}{RareItem} * abs $type->ood($map->{Depth}));
    push @stuff, $type;
  }

  for (1 .. random(@{ CFG->{DunGen}{NumBaddies} })) {
    debug("WARNING no monsters in range. too high a dungeon"), last unless @baddies;
    my $type = choosernd(@baddies);
    my $new = $type->new(Map => $map);
    if ($new->void) {
      debug("WARNING $type spawn failed");
    }
    if ($type->Pack) {
      log_this("spawning more " . $type->type . " in a pack");
      # have more monsters than normal, yeah.
      foreach (1 .. random(3, 5)) {
        $type->new(
          Map => $map,
          At => [$map->getpt($new->{Y} - 3, $new->{X} - 5, $new->{Y} + 3, $new->{X} + 5)]
        );
      }
    }
  }
  for (1 .. random(@{ CFG->{DunGen}{NumStuff} })) {
    debug("WARNING no items in range. too high a dungeon"), last unless @stuff;
    my $type = choosernd(@stuff);
    $type->new(
      On   => $map,
      OOD  => $type->ood($map->{Depth})    # Let each constructor handle this
    );
  }
}

42;
