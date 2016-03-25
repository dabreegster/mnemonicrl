#####################
# StdLib::Character #
#####################

package Roguelike::StdLib::Character;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

# Definition

my $char = $Game->{Templates}{Obj}->new(
  Sustenance => 0,
  Equipment => {
    Helmet => undef,
    Amulet => undef,
    Armour => undef,
    Gloves => undef,
    LeftRing  => undef,
    RightRing => undef,
    Boots  => undef,
    Weapon => undef
  },
  Queue => [],
  Z => 0,
  Y => 0,
  X => 0,
  Init => sub {
    my $self = shift;
    # Whoa, wait, are we an instance? If we are, we have Z, Y, and X. No base.
    if (defined $self->{Z} and defined $self->{Y} and defined $self->{X}) {
      # Evaluate random stats.
      foreach my $stat (qw( Str Def HP TP Exp )) {
        if (ref $self->g($stat) eq "ARRAY") {
          $self->{$stat} = random(@{ $self->g($stat) });
        } else {
          $self->{$stat} = $self->g($stat);
        }
        $self->{"Max$stat"} = $self->{$stat};
      }
      # Wield and wear what needs to be wielded or worn
      if (my $weapon = $self->g("Wielding")) {
        # Get it first!
        my $new = new $weapon;
        $self->{Inv}->add($new);
        $self->wield($new);
      }
      if (ref $self->g("Wearing") eq "ARRAY") {
        # Either could be [$item, $slot] or [$item, $item, [$item, $slot]]
        # I'm lazy, so it's a list. :)
        foreach (@{ $self->g("Wearing") }) {
          if (ref $_ eq "ARRAY") {
            my $new = $_->[0]->new;
            $self->{Inv}->add($new);
            $self->equip($new, $_->[1]);
          } else {
            my $new = $_->new;
            $self->{Inv}->add($new);
            $self->wear($new);
          }
        }
      } elsif ($self->g("Wearing")) {
        my $new = $self->g("Wearing")->new;
        $self->{Inv}->add($new);
        $self->wear($new);
      }
      # Schedule our stat managers.
      unless ($self->{StatManager}) {
        $self->delayevent(3, sub {
          $self->{HP}++ unless $self->{HP} == $self->g("MaxHP");
          return -42;
        });
        $self->delayevent(5, sub {
          # Are we full?
          $self->{TP}++ unless $self->{TP} == $self->g("MaxTP");
          return -42;
        });
        $self->{StatManager} = 1;
      } else {
        render($self->tile);  # We're in the second pass
      }
    }
  },
  Close_Attack => sub {
    my $self = shift;
    return "weapon_attack" if $self->g("Equipment.Weapon");
    return "unarmed_attack";
  },
  Attacks => {
    weapon_attack => {
      TP => 0,
      Action => sub {
        my ($self, $enemy) = @_;
        # We're assuming $enemy is adjacent to $self.
        # Assume we always hit.
        my $damage = 0;
        $damage += $self->g("Str");
        $damage -= $enemy->g("Def");
        $damage += $self->g("Equipment.Weapon")->rating;
        $damage -= $enemy->g("Equipment.Armour")->rating if $enemy->g("Equipment.Armour");
        # Deduct durability from equipment
        $self->g("Equipment.Weapon")->diminish;
        $enemy->g("Equipment.Armour")->diminish if $enemy->g("Equipment.Armour");
        if ($damage > 0) {
          $self->msg("[3P] [2] inflicts $damage damage on [1].", $enemy, $self->g("Equipment.Weapon"), $self);
          $enemy->take_damage($damage);
          return 1;
        } else {
          $self->msg("[1P] attack against [2] was ineffective.", $self, $enemy);
          return -1;
        }
      }
    },
    unarmed_attack => {
      TP => 0,
      Action => sub {
        my ($self, $enemy) = @_;
        # We're assuming $enemy is adjacent to $self.
        # Assume we always hit.
        my $damage = 0;
        $damage += $self->g("Str");
        $damage -= $enemy->g("Def");
        $damage -= $enemy->g("Equipment.Armour")->rating if $enemy->g("Equipment.Armour");
        # Deduct durability from equipment
        $enemy->g("Equipment.Armour")->diminish if $enemy->g("Equipment.Armour");
        if ($damage > 0) {
          $self->msg("[subj] [inflict] $damage damage on [1].", $enemy);
          $enemy->take_damage($damage);
          return 1;
        } else {
          $self->msg("[1P] attack against [2] was ineffective.", $self, $enemy);
          return -1;
        }
      }
    },
    shoot => {
      TP => 0,
      Action => sub {
        my ($self, $direction) = @_;
        # Distance is a factor.
        # No durability.
        # Get target. Singular.
        my $target = ($self->g("Area")->trace(
          $self->g("Z"),
          $self->g("Y"),
          $self->g("X"),
          $direction
        ))[0];
        my $weapon = $self->g("Equipment.Weapon");
        unless ($target) {
          $self->msg("[1P] [2] hits nothing.", $self, $weapon);
          return -1;
        }
        # Distance is a factor.
        my $distance = abs($self->{Y} - $target->{Y}) + abs($self->{X} - $target->{X});
        # Er, use?
        my $damage = $weapon->rating - $distance;
        if ($damage > 0) {
          $self->msg("[1P] [2] slices away $damage HP from [3].", $self, $weapon, $target);
          $target->take_damage($damage);
          return 1;
        } else {
          $self->msg("[1P] [2] fails to hurt [3].", $self, $weapon, $target);
          return -1;
        }
      }
    }
  },
  Str => 0,
  Def => 0,
  HP => 0,
  TP => 0,
  Level => 0,
);

# Reactions

$char->react(
  to => ["After", "hit"],
  by => sub {
    my $self = shift;
    # Force to input.
    $self->{Queue} = [];
    $self->schedule(1, sub { $self->Input(); });
  }
);

# Actions

sub PRE_move_n { (-42, "move", "n") }
sub PRE_move_Dk { (-42, "move", "n") }

sub PRE_move_s { (-42, "move", "s") }
sub PRE_move_Dj { (-42, "move", "s") }

sub PRE_move_e { (-42, "move", "e") }
sub PRE_move_Dl { (-42, "move", "e") }

sub PRE_move_w { (-42, "move", "w") }
sub PRE_move_Dh { (-42, "move", "w") }

sub PRE_move_ne { (-42, "move", "ne") }
sub PRE_move_Du { (-42, "move", "ne") }

sub PRE_move_nw { (-42, "move", "nw") }
sub PRE_move_Dy { (-42, "move", "nw") }

sub PRE_move_se { (-42, "move", "se") }
sub PRE_move_Dn { (-42, "move", "se") }

sub PRE_move_sw { (-42, "move", "sw") }
sub PRE_move_Db { (-42, "move", "sw") }

sub PRE_move {
  my ($self, $dir) = @_;
  $dir = lc $dir;
  my $y = $self->g("Y");
  my $x = $self->g("X");
  $y-- if $dir eq "n";
  $y++ if $dir eq "s";
  $x-- if $dir eq "w";
  $x++ if $dir eq "e";
  $y--, $x-- if $dir eq "nw";
  $y--, $x++ if $dir eq "ne";
  $y++, $x-- if $dir eq "sw";
  $y++, $x++ if $dir eq "se";
  # Check for valid coordinates.
  if ($self->g("Area.Wrap")) {
    $y = 0 if $y > $self->g("Area")->height;
    $x = 0 if $y > $self->g("Area")->width;
      $y = $self->g("Area")->height if $y == -1;
      $x = $self->g("Area")->width if $y == -1;
  } else {
    return -1 if $y < 0 or $y > $self->g("Area")->height;
    return -1 if $x < 0 or $x > $self->g("Area")->width;
  }
  return (-42, "go", $y, $x);
}

sub PRE_go {
  my $self = shift;
  my ($y, $x, $z, $area);
  if (@_ == 2) {
    ($y, $x) = @_;
    $z = $self->g("Z");
  } elsif (@_ == 3) {
    ($z, $y, $x) = @_;
    unless (ref $area) {
      $area = $Game->{Levels}[$z];
    }
  }
  return -1 if $self->tile and $z == $self->g("Z") and $y == $self->g("Y") and $x == $self->g("X");
  $area ||= $self->g("Area");
  my $tile = $area->{Map}[$y][$x];
  return (-42, $self->g("Close_Attack"), $tile->{Char}) if $tile->{Char};
  return (-42, "open", $y, $x) if $tile->{_} eq "+";
  return -1 if $area->barrier($y, $x);
  return (1, "go", $z, $y, $x);
}

sub go {
  my $self = shift;
  my ($z, $y, $x) = @_;
  # Junk the old, if there is anything
  if ($self->tile) {
    $self->tile->{Char} = undef;
    render($self->tile);
  }
  my $area = $Game->{Levels}[$z];
  $self->{Area} = $area;
  $self->{Z} = $z;
  $self->{Y} = $y;
  $self->{X} = $x;
  $self->tile->{Char} = $self;
  render($self->tile);
  return 1;
}

sub PRE_exit { (0, "exit") }

sub PRE_test { (0, "test") }

sub PRE_test2 { (0, "test2") }

sub PRE_msglog { (0, "msglog") }

sub PRE_get {
  my $self = shift;
  my @items = @_;
  # If we have no items, ask the UI.
  unless (@items) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    my $container = $self->tile->{Inv};
    if (scalar @{ $container->{List} } == 0) {
      say "There's nothing here, fool!";
      return -1;
    } elsif (scalar @{ $container->{List} } == 1) {
      push @items, $container->get(0);
    } else {
      say "There are " . scalar @{ $container->{List} } . " items here";
      my $all = 0;
      foreach my $obj (reverse $container->all) {
        if ($all) {
          push @items, $obj;
          next;
        }
        say "Pick up " . $obj->name . "? (y,n,a,q)";
        $Game->{UI}->msgrefresh(1);
        my $in = $Game->{UI}->prompt;
        last if $in eq "q";
        @items = (), last if $in eq "^["; # Escape!
        if ($in eq "a") {
          $all = 1;
          push @items, $obj;
          next;
        }
        push @items, $obj if $in eq "y";
      }
      unless (scalar @items) {
        say "None of it was worth it anyway.";
        return -1;
      }
    }
  }
  # Once we do, check to make sure they're all on self's tile.
  foreach (@items) {
    if ($self->tile->{Inv}->get( $_->g("Index") )->g("ID") != $_->g("ID")) {
      $self->msg("[1] isn't beneath [subj].", $_);
      return -1;
    }
  }
  return (scalar @items, "get", @items);
}

sub get {
  my ($self, @items) = @_;
  foreach my $obj (@items) {
    # Delete from old tile. Dang reference counting.
    my $item = $obj->g("Area")->del( $obj->g("Index") );
    # Give it to character
    $item = $self->{Inv}->add($item);
    # Bypass msg... NO POINT
    say $item->g("Index") . " - " . $item->name if $self->g("ID") ==
    $Player->g("ID");
  }
  # Bug? Still looking at old objs, possibly not new items?
  if ($self->g("ID") != $Player->g("ID")) {
    my $names;
    if (scalar @items == 1) {
      $names = $items[0]->name;
    } elsif (scalar @items == 2) {
      $names = $items[0]->name . " and " . $items[1]->name;
    } else {
      my $last = pop @items;
      $names = join ", ", map { $_->name } @items;
      $names .= "and " . $last->name;
    }
    $self->msg("[subj] picks up $names.");
  }
  return 1;
}

sub PRE_drop {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    $item = $Game->{UI}->selectinv($self, "Drop what?");
    return -1 if $item == -1;
  }
  # Do we even have $item?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  # Is it equipped?
  if ($item->g("On") and $self->g("Equipment." . $item->g("On") . ".ID")
      == $item->g("ID")
     )
  {
  my $pri = 1;
  $pri = 0 if $item->g("On") eq "Weapon";
  $self->schedule($pri, $self->queue("drop", $item), "unequip");
    return (-42, "unequip", $item);
  }
  return (1, "drop", $item);
}

sub drop {
  my ($self, $obj) = @_;
  # Take from character...
  my $item = $obj->{Area}->del( $obj->g("Index") );
  # And put on the tile.
  $self->tile->{Inv}->add($item);
  $self->msg("[subj] [drop] [1].", $obj);
  return 1;
}

sub PRE_idle { (1, "idle") }

sub idle {
  my $self = shift;
  # Boy, wasn't this command hard to write!
  return 1;
}

sub PRE_wield {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    $item = $Game->{UI}->selectinv(
      $self, "Wield what? (- for none)", ["Weapons"], ["-"]
    );
    return -1 if $item eq -1;
  }
  if ($item eq "-") {
    if ($self->g("Equipment.Weapon")) {
      return (-42, "unequip", $self->g("Equipment.Weapon"));
    } else {
      $self->msg("[subj] [aren't/isn't] wielding anything!");
      return -1;
    }
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  if ($item->g("ID") == $self->g("Equipment.Weapon.ID")) {
    $self->msg("[subj] [are/is] already wielding [1].", $item);
    return -1;
  }
  # Is it wieldable?
  unless ($item->g("Wieldable")) {
    $self->msg("[subj] can't wield [1].", $item);
    return -1;
  }
  return (-42, "equip", $item, "Weapon");
}

sub PRE_wear {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    $item = $Game->{UI}->selectinv($self, "Put on what?", ["Armour"]);
    return -1 if $item == -1;
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  # Can we wear it or is it already being worn?
  # Wieldable too? Hey, it's convenient.
  if (!$item->g("Wearable") and !$item->g("Wieldable")) {
    $self->msg("[subj] can't wear [1].", $item);
    return -1;
  } elsif ($item->g("On")) {
    $self->msg("[subj] [are/is] already wearing [1].", $item);
    return -1;
  }
  # On which slot do we equip $item?
  my @slots;
  foreach (@{ $item->g("Fits") }) {
    push @slots, $_ unless $self->g("Equipment.$_");
  }
  @slots = @{ $item->g("Fits") } unless @slots;
  if (scalar @slots == 1) {
    return (-42, "equip", $item, $slots[0]);
  } elsif (scalar @slots == 0) {
    debug "Hey, this can't be worn anywhere! " . $item->name;
    return -1;
  } else {
    if ($self->{ID} == $Player->{ID}) {
      my $choices = {
        map {
          if ($_ eq "LeftRing") {
            ("l", $_);
          } elsif ($_ eq "RightRing") {
            ("r", $_);
          } else {
            debug "WARNING! This item is tough to select as a choice!";
          }
        } @slots
      };
      my $slot = $Game->{UI}->selectchoice(
        $choices, "Put " . $item->g("Name") . " on? ("  .
                  join(", ", keys %$choices) .")"
      );
      if ($slot eq "-1") {
        return -1;
      } else {
        return (-42, "equip", $item, $slot);
      }
    } else {
      return (-42, "equip", $item, $slots[0]);
    }
  }
}

sub PRE_takeoff {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    $item = $Game->{UI}->selectinv($self, "Take off what?", ["Armour"]);
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    return -1 if $item == -1;
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  # Is it worn?
  unless ($item->g("On")) {
    $self->msg("[subj] [aren't/isn't] wearing [1].", $item);
    return -1;
  }
  return (-42, "unequip", $item);
}

sub PRE_read {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    $item = $Game->{UI}->selectinv($self, "Read what?", ["Scroll"]);
    return -1 if $item == -1;
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  unless ($item->g("Readable")) {
    $self->msg("[subj] can't read [1].", $item);
    return -1;
  }
  return (1, "read", $item);
}

sub read {
  # Scrolls only. Tomes should be delegated to the browse/memorize action.
  my ($self, $scroll) = @_;
  # Events do the real work of course.
  $scroll->destroy;
  $self->msg("[subj] [read] [1].", $scroll);
  return 1;
}

sub PRE_quaff {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    $item = $Game->{UI}->selectinv($self, "Drink what?", ["Potion"]);
    return -1 if $item == -1;
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  unless ($item->g("Drinkable")) {
    $self->msg("[subj] can't drink [1].", $item);
    return -1;
  }
  return (1, "quaff", $item);
}

sub quaff {
  my ($self, $potion) = @_;
  # Events do the real work of course.
  $potion->destroy;
  $self->msg("[subj] [drink] [1].", $potion);
  return 1;
}

sub PRE_eat {
  my $self = shift;
  my $item = shift;
  unless ($item) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    $item = $Game->{UI}->selectinv($self, "Eat what?", ["Food"]);
    return -1 if $item == -1;
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  unless ($item->g("Edible")) {
    $self->msg("[subj] can't eat [1].", $item);
    return -1;
  }
  return (1, "eat", $item);
}

sub eat {
  my ($self, $food) = @_;
  # Replenish the character's sustenence.
  $self->{Sustenance} += $food->g("Sustenance");
  $self->msg("[subj] [eat] [1].", $food);
  $food->destroy;
  return 1;
}

sub PRE_equip {
  my ($self, $item, $slot) = @_;
  # Do we have item?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] have [1].", $item);
    return -1;
  }
  # Can it be equipped there?
  my $fits = 0;
  foreach (@{ $item->g("Fits") }) {
    $fits = 1, last if $_ eq $slot;
  }
  unless ($fits) {
    ### FIXME: Possessive! your/[subj]'s
    $self->msg("[1] doesn't fit on " . lc $slot . ".", $item);
  }
  # Is there something already there?
  if ($self->g("Equipment.$slot")) {
    $self->schedule(1, $self->queue("equip", $item, $slot), "unequip");
    return (-42, "unequip", $self->g("Equipment.$slot"));
  } else {
    return (1, "equip", $item, $slot);
  }
}

sub equip {
  my $self = shift;
  my $item = shift;
  my $slot = shift;
  $self->{Equipment}{$slot} = $item;
  $item->{On} = $slot;
  if ($slot eq "Weapon") {
    $self->msg("[subj] [wield] [1].", $item);
  } else {
    $self->msg("[subj] [put] on [1].", $item);
  }
  return 1;
}

sub PRE_unequip {
  my ($self, $item) = @_;
  # Item might be a slot!
  unless (ref $item) {
    if ($self->g("Equipment.$item")) {
      $item = $self->g("Equipment.$item");
    } else {
      $self->msg("[subj] [haven't/hasn't] got anything equipped on " . lc $item . "!");
      return -1;
    }
  }
  # Do we have it?
  unless ($self->has($item)) {
    $self->msg("[subj] [don't/doesn't] even have [1].", $item);
    return -1;
  }
  # Is it equipped by $self?
  my $slot = $item->g("On");
  if ((!$slot) or $self->g("Equipment.$slot.ID") != $item->g("ID")) {
    $self->msg("[subj] [aren't/isn't] equipping [1].", $item);
    return -1;
  }
  # Is it cursed?
  if ($item->g("Cursed")) {
    $self->msg("[subj] can't rid yourself of [1]; it's cursed!", $item);
    return -1;
  } else {
    return (1, "unequip", $item);
  }
}

sub unequip {
  my $self = shift;
  my $item = shift;
  $self->{Equipment}{ $item->g("On") } = undef;
  my $slot = $item->g("On");
  if ($slot eq "Weapon") {
    $self->msg("[subj] [unwield] [1].", $item);
  } else {
    $self->msg("[subj] [take] off [1].", $item);
  }
  $item->{On} = undef;
  return 1;
}

sub PRE_open {
  my $self = shift;
  my ($y, $x) = @_;
  # Do we have coordinates?
  unless (defined $y and defined $x) {
    $y = $Player->g("Y");
    $x = $Player->g("X");
    my $map = $self->g("Area.Map");
    # Find adjacent doors.
    my @doors;
    push @doors, [$y, $x - 1] if $map->[$y][$x - 1]{_} eq "+";
    push @doors, [$y, $x + 1] if $map->[$y][$x + 1]{_} eq "+";
    push @doors, [$y - 1, $x  - 1] if $map->[$y - 1][$x - 1]{_} eq "+";
    push @doors, [$y - 1, $x + 1] if $map->[$y - 1][$x + 1]{_} eq "+";
    push @doors, [$y + 1, $x - 1] if $map->[$y + 1][$x - 1]{_} eq "+";
    push @doors, [$y + 1, $x + 1] if $map->[$y + 1][$x + 1]{_} eq "+";
    push @doors, [$y - 1, $x] if $map->[$y - 1][$x]{_} eq "+";
    push @doors, [$y + 1, $x] if $map->[$y + 1][$x]{_} eq "+";
    if (@doors == 0) {
      say "There are no doors nearby to open.";
      return -1;
    } elsif (@doors == 1) {
      ($y, $x) = @{ $doors[0] };
    } else {
      debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
      say "Open which door?";
      say "TODO: Targetting system!!!";
      return -1;
    }
  }
  # Is the tile closed, open, or not even a door?
  my $tile = $self->g("Area.Map.$y.$x");
  if ($tile->{Char}) {
    say "There's somebody in the doorway!";
    return -1;
  } elsif ($tile->{_} eq "+") {
    return (1, "open", $y, $x);
  } elsif ($tile->{_} eq "'") {
    say "That door is already open!";
    return -1;
  } else {
    say "That's not even a door!";
    return -1;
  }
}

sub open {
  my $self = shift;
  my ($y, $x) = @_;
  $self->{Area}{Map}[$y][$x]{_} = "'";
  render($self->{Area}{Map}[$y][$x]);
  $self->msg("[subj] [open] the door.");
  return 1;
}

sub PRE_close {
  my $self = shift;
  my ($y, $x) = @_;
  # Do we have coordinates?
  unless (defined $y and defined $x) {
    $y = $Player->g("Y");
    $x = $Player->g("X");
    my $map = $self->g("Area.Map");
    # Find adjacent doors.
    my @doors;
    push @doors, [$y, $x - 1] if $map->[$y][$x - 1]{_} eq "'";
    push @doors, [$y, $x + 1] if $map->[$y][$x + 1]{_} eq "'";
    push @doors, [$y - 1, $x  - 1] if $map->[$y - 1][$x - 1]{_} eq "'";
    push @doors, [$y - 1, $x + 1] if $map->[$y - 1][$x + 1]{_} eq "'";
    push @doors, [$y + 1, $x - 1] if $map->[$y + 1][$x - 1]{_} eq "'";
    push @doors, [$y + 1, $x + 1] if $map->[$y + 1][$x + 1]{_} eq "'";
    push @doors, [$y - 1, $x] if $map->[$y - 1][$x]{_} eq "'";
    push @doors, [$y + 1, $x] if $map->[$y + 1][$x]{_} eq "'";
    if (@doors == 0) {
      say "There are no doors nearby to close.";
      return -1;
    } elsif (@doors == 1) {
      ($y, $x) = @{ $doors[0] };
    } else {
      debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
      say "Close which door?";
      say "TODO: Targetting system!!!";
      return -1;
    }
  }
  # Is the tile closed, open, or not even a door?
  my $tile = $self->g("Area.Map.$y.$x");
  if ($tile->{Char}) {
    say "There's somebody in the doorway!";
    return -1;
  } elsif ($tile->{_} eq "'") {
    return (1, "close", $y, $x);
  } elsif ($tile->{_} eq "+") {
    say "That door is already closed!";
    return -1;
  } else {
    say "That's not even a door!";
    return -1;
  }
}

sub close {
  my $self = shift;
  my ($y, $x) = @_;
  $self->{Area}{Map}[$y][$x]{_} = "+";
  render($self->{Area}{Map}[$y][$x]);
  $self->msg("[subj] [close] the door.");
  return 1;
}

sub PRE_descend {
  my $self = shift;
  my $tile = $self->tile;
  # Is there a staircase here? What kind?
  if ($tile->{_} eq "<") {
    say "The staircase here leads up, not down.";
    return -1;
  } elsif ($tile->{_} ne ">") {
    say "There isn't a staircase here.";
    return -1;
  }
  return (1, "descend");
}

sub descend {
  my $self = shift;
  my $tile = $self->tile;
  unless ($Game->{Levels}[ $self->g("Z") + 1 ]) {
    my $style = "Dungeon";
    if ($self->g("Z") + 1 >= 16) {
      $Game->addlevel($style, 75, 150, 7);
    } else {
      if (percent(40)) {
        $style = chooserand("Maze", "Building", "Tunnel", "Cellular");
      }
      $Game->addlevel($style, 50, 100, 6);
    }
  }
  # This is messy. Player only. RM old baddies from queue.
  if ($self->g("ID") == $Player->g("ID")) {
    my %ids = map { $_->{ID} => 1 } @{ $self->g("Area.Monsters") };
    my $tmp = [];
    foreach (0 .. $#{ $Game->{Queue} }) {
      push @$tmp, $Game->{Queue}[$_] unless $ids{ $Game->{Queue}[$_]{Actor}{ID} };
    }
    @{ $Game->{Queue} } = @{ $tmp };
  }
  my ($y, $x) = @{ $Game->{Levels}[ $self->g("Z") + 1 ]{StairsUp}[$tile->{Stair} ] };
  $self->go($self->g("Z") + 1, $y, $x);
  # This is a MESSY hack.
  delete $Game->{Messages}[-1];
  $self->msg("[subj] descend another level.");
  # This is messy. Player only. Add new baddies to queue.
  if ($self->g("ID") == $Player->g("ID")) {
    foreach my $baddie (@{ $self->g("Area.Monsters") }) {
      $baddie->schedule(1, sub { $baddie->Input(); }) unless $baddie->{Queue}[0];
      $Game->{Queue}->add( pop @{ $baddie->{Queue} } );
    }
  }
  return 1;
}

sub PRE_ascend {
  my $self = shift;
  my $tile = $self->tile;
  # Is there a staircase here? What kind?
  if ($tile->{_} eq ">") {
    say "The staircase here leads down, not up.";
    return -1;
  } elsif ($tile->{_} ne "<") {
    say "There isn't a staircase here.";
    return -1;
  }
  return (1, "ascend");
}

sub ascend {
  my $self = shift;
  if ($self->g("Z") - 1 < 0) {
    $self->msg("[subj] [leave] the dungeon.");
    $Game->{UI}->msgrefresh;
    $self->exit;  # Assume we're Player.
  }
  # This is messy. Player only. RM old baddies from queue.
  if ($self->g("ID") == $Player->g("ID")) {
    my %ids = map { $_->{ID} => 1 } @{ $self->g("Area.Monsters") };
    my $tmp = [];
    foreach (0 .. $#{ $Game->{Queue} }) {
      push @$tmp, $Game->{Queue}[$_] unless $ids{ $Game->{Queue}[$_]{Actor}{ID} };
    }
    @{ $Game->{Queue} } = @{ $tmp };
  }
  my $tile = $self->tile;
  my ($y, $x) = @{ $Game->{Levels}[ $self->g("Z") - 1 ]{StairsDown}[$tile->{Stair} ] };
  $self->go($self->g("Z") - 1, $y, $x);
  # This is a MESSY hack
  delete $Game->{Messages}[-1];
  $self->msg("[subj] ascend another level.");
  # This is messy. Player only. Add new baddies to queue.
  if ($self->g("ID") == $Player->g("ID")) {
    foreach my $baddie (@{ $self->g("Area.Monsters") }) {
      $baddie->schedule(1, sub { $baddie->Input(); }) unless $baddie->{Queue}[0];
      $Game->{Queue}->add( pop @{ $baddie->{Queue} } );
    }
  }
  return 1;
}

sub PRE_attack {
  my $self = shift;
  my $attack = shift;
  # Does $self have $attack?
  unless ($self->g("Attacks.$attack")) {
    debug "$self->{ID} can't $attack!";
    return -1;
  }
  # Enough TP?
  if ($self->g("TP") < $self->g("Attacks.$attack.TP")) {
    $self->msg("[subj] doesn't have enough TP to $attack!");
    return -1;
  }
  return (1, "attack", $attack, @_);
}

sub UTIL_attack {
  my $self = shift;
  my $attack = shift;
  # Execute!
  return -1 if signal("Before", $self, "attack", @_) == -1;
  my $return = $self->g("Attacks.$attack.Action", $self, @_);;
  # Deduct TP if need be.
  $self->{TP} -= $self->g("Attacks.$attack.TP");
  signal("After", $self, "attack", @_);
  return $return;
}

sub PRE_weapon_attack {
  my $self = shift;
  unless ($self->g("Equipment.Weapon")) {
    $self->msg("[1] has no weapon with which to attack!");
  }
  return (-42, "attack", "weapon_attack", @_);
}

sub PRE_unarmed_attack {
  my $self = shift;
  return (-42, "attack", "unarmed_attack", @_);
}

sub UTIL_take_damage {
  my ($self, $damage) = @_;
  # We're simple for now!
  $self->{HP} -= $damage;
  # Dead?
  $self->die if $self->g("HP") < 1;
  return 1;
}

sub PRE_shoot {
  my $self = shift;
  my $dir = shift;
  unless ($self->g("Equipment.Weapon")) {
    $self->msg("[subj] [aren't/isn't] even wielding anything!");
    return -1;
  }
  unless ($self->g("Equipment.Weapon.Ranged")) {
    $self->msg("[1P] [2] isn't a ranged weapon!", $self, $self->g("Equipment.Weapon"));
    return -1;
  }
  unless ($dir) {
    debug "Need args", return -1 unless $self->{ID} == $Player->{ID};
    my $choices = { map { $_ => $_ } qw(h j k l y u b n) };
    $dir = $Game->{UI}->selectchoice(
      $choices, "Shoot where? (hjklyubn)"
    );
    return -1 if $dir eq -1;
  }
  return (-42, "attack", "shoot", $dir);
}

define(
  Character => $char,
  [
    "go", "get", "drop", "idle", "read", "quaff", "eat", "equip", "unequip",
    "open", "close", "ascend", "descend",
  ]
);

42;
