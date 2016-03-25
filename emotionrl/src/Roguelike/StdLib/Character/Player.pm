#############################
# StdLib::Character::Player #
#############################

package Roguelike::StdLib::Character::Player;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Container;

# Definition

my $pc = $Game->{Templates}{Character}->new(
  Name => "Player",
  Symbol => "@",  # Ah, the nostalgia...
  #Unique => 1,    # How's this tie in with races and classes?
  Init => sub {
    my $self = shift;
    # We're always an instance, right?
    # Set up some stuff up...
    $self->{Inv} = new Roguelike::Container 1, $self;
    $self->schedule(1, sub { $self->Input() });
    unless (defined $self->{Y} and defined $self->{X}) {  # No base
      my $dat = chooserand(@{ $Game->{Levels}[ $self->g("Z") ]{StairsUp} });
      ($self->{Y}, $self->{X}) = @$dat;
    }
    $self->go( $self->g("Z"), $self->g("Y"), $self->g("X") );
    $self->levelup;
    return 1;
  },
  Actions => {
    exit => sub {
      # This subroutine name might not work so well with the exporter. :P
      # Temporary, this is, of course
      exit;
    }
  },
  Level => 0,
  Exp => 0,
  ExpNeeded => 0,
  Techniques => {},
  ModeLaugh => 0  # EWWWWWW
);

# Reactions

$pc->react(
  to => ["After", "go"],
  by => sub {
    my $self = shift;
    $self->list(1);
    return 1;
  },
  Static => 1
);

# Actions

sub PRE_exit { 
  shift;
  my $force = shift;
  my $in;
  unless ($force) {
    say "Do you really want to quit? (Yn)";
    $Game->{UI}->msgrefresh;
    $in = $Game->{UI}->prompt;
  }
  if ($force or $in eq "Y") {
    return (0, "exit");
  } else {
    return -1;
  }
}

sub UTIL_AfterTurn {
  # A turn, from the real-life player's perspective, is how many actions
  # they've taken.
  $Game->{Turns}++;
  $Game->{UI}->refresh;
  $Game->{UI}->statrefresh;
}

sub UTIL_Input {
  my $self = shift;
  my ($dothis, $energy);
  $self->AfterTurn;
  while (1) {
    $energy = 1;
    $Game->{UI}->msgrefresh();
    my $in = $Game->{UI}->prompt;
    my $action = $Game->{UI}{Keymap}{$in};
    unless ($action) {
      say "The $in key is not bound.";
      next;
    }
    $action = "_$action";
    my ($meth, @args);
    my @results = $self->$action();
    if (@results == 1) {
      $energy = -1;
    } else {
      ($energy, $meth, @args) = @results;
    }
    next if $energy == -1;
    $meth = "_${meth}_";
    if ($energy == 0) {
      $self->$meth(@args);
      next;
    } elsif ($energy == 1) {
      $self->queue($meth, @args)->();
      return 1;
    } else {
      $dothis = $self->queue($meth, @args);
      last;
    }
  }
  $self->schedule($energy, $dothis);
  return 1;
}

sub PRE_test { (0, "test") }

sub test {
  #complain "Multi-colored <green>monstrosity!";
  #say "boring plain grey";
  #say "<purple>foo<white>bar";
  #say "Long, infinitely LONGISH sorts of lines that appear to go on for
  #     infinity captivate and... imaginate? the imagination for all of
  #     eternity, as visible in the eye of the <green>beholder<aqua>WEE!";
  #say "But when light fades... will the hero rise again?";
  #say "<RED>bright colors <GREEN>as opposed to <grey>dim colors";
  #$Game->{UI}->msgbox("Long, infinitely LONGISH sorts of lines that appear to
  #go on for infinity captivate and... imaginate? the imagination for all of
  #eternity, as visible in the eye of the <green>beholder<aqua>WEE!");
  #$Game->save();
}

sub PRE_test2 { (0, "test2") }

sub test2 {
  my $self = shift;
  my $map = $self->g("Area");
  open FOO, ">demomap";
  foreach my $y (0 .. $map->height) {
    foreach my $x (0 .. $map->width) {
      print FOO $map->{Map}[$y][$x]{_};
    }
    print FOO "\n";
  }
  close FOO;
  return 1;
}

sub PRE_msglog { (0, "msglog") }

sub msglog {
  $Game->{UI}->display(0, $Game->{UI}{MsgFilters}, @{ $Game->{MsgLog} });
}

sub PRE_inv { (0, "inv", "-") }

sub inv {
  my $self = shift;
  my $mode = shift;
  $mode = defined $mode ? $mode : 0;
  my @categories;
  if (@_) {
    @categories = @_;
  } else {
    @categories = keys %{ $Game->{Config}{Category} };
  }
  my @lines = ("<yellow>Inventory", "");
  foreach my $cat (@categories) {  # Dog... GRANDMA!!!
    push @lines, " <RED>$cat" if keys %{ $Player->{Inv}{Category}{$cat} };
    foreach (sort keys %{ $Player->{Inv}{Category}{$cat} }) {
      push @lines, "  $_ - " . $Player->{Inv}->get($_)->name;
    }
  }
  return $Game->{UI}->display($mode, [], @lines);
}

sub PRE_list { (0, "list", "-") }

sub list {
  my $self = shift;
  my $indirect = shift;
  my $inv = $self->tile->{Inv};
  say "There's a staircase leading up here." if $self->tile->{_} eq "<";
  say "There's a staircase leading down here." if $self->tile->{_} eq ">";
  say "You stand in a doorway." if $self->tile->{_} eq "'" and !$indirect;
  if (defined $inv->get(0)) {
    say "You see here:";
    foreach (reverse $inv->all) {
      say " " . $_->name;
    }
  } else {
    say "There's nothing here." unless $indirect;
  }
  return 1;
}

sub PRE_redo { (0, "redo") }

sub redo {
  my $self = shift;
  # Clear the random numbers
  $Game->{Random}{Used} = [];
  $Game->{Random}{Queued} = [];
  use Roguelike::Area::Dungeon;
  $self->{Area}{Map}[ $self->{Y} ][ $self->{X} ]{Char} = undef;
  $self->{Area} = Roguelike::Area::Dungeon->generate(50, 100, 3);
  $self->go( $self->g("Area"), $self->g("Y"), $self->g("X") );
  render($self->{Area}{Map}[ $self->{Y} ][ $self->{X} ]);
  $Game->{UI}->refresh;
  return 1;
}

sub PRE_viewinv {
  my $self = shift;
  my $item = $Game->{UI}->selectinv($self, "Examine what?");
  return -1 if $item == -1;
  $Game->{UI}->msgrefresh;
  return (0, "examine", $item);
}

sub PRE_examine { (0, "examine", "-") }

sub examine {
  my ($self, $item) = @_;
  my @lines;
  push @lines, "<Aqua>" . $item->g("Index") . " - " . $item->name, "";
  push @lines, $item->g("Desc"), "" if $item->g("Desc");
  if ($item->g("Wearable") or $item->g("Wieldable")) {
    push @lines, "<red>Power: <grey>" . $item->g("Power"),
                 "<red>Bonus Modifier:<grey> " . $item->g("Mod"),
                 "";
  }
  return $Game->{UI}->display(1, [], @lines);
}

sub PRE_examinemons { (0, "examinemons", "-") }

sub examinemons {
  my ($self, $monster) = @_;
  my @lines;
  push @lines, "<Aqua>" . $monster->name, "";
  push @lines, $monster->g("Desc"), "";
  push @lines, "<red>HP: <grey>" . $monster->g("HP");
  push @lines, "<red>TP: <grey>" . $monster->g("TP");
  push @lines, "<red>Strength: <grey>" . $monster->g("Str");
  push @lines, "<red>Defence: <grey>" . $monster->g("Def");
  push @lines, "<red>Experience: <grey>" . $monster->g("Exp");
  return $Game->{UI}->display(1, [], @lines);
}

sub PRE_die { (0, "die") }

sub die {
  my $self = shift;
  say "You die...";
  $Game->{UI}->refresh;
  $Game->{UI}->msgrefresh;
  $Game->{UI}->statrefresh;
  $Game->{UI}->prompt;
  $Game->{UI}->msgbox(1,
    "You awaken to the same life you had when you entered the dream. You feel
     as if you should go back and try again."
  );
  $Player->exit(1);
}

sub UTIL_gainexp {
  my $self = shift;
  my $exp = shift;
  # Add it.
  $self->{Exp} += $exp;
  # Enough?
  my $carryover = 0;
  if ($self->{Exp} >= $self->g("ExpNeeded")) {
    $carryover = $self->{Exp} - $self->g("ExpNeeded");
    $self->{Exp} = 0;
    $self->levelup;
  }
  $self->{Exp} += $carryover; # We'll *assume* we don't have enough carryover
                              # to actually make us go another level!
  return 1;
}

sub UTIL_levelup {
  my $self = shift;
  $self->{Level}++;
  $self->msg("<Green>[subj] [have/has] gained a level!");
  $self->{ExpNeeded} = 25 * $self->{Level};
  # Raise mah stats
  my $hp = min(2, 5, 10);
  my $tp = random(2, 4);
  my $str = random(1, 3);
  my $def = random(1, 3);
  $self->{HP} += $hp;
  $self->{MaxHP} += $hp;
  $self->{TP} += $tp;
  $self->{MaxTP} += $tp;
  $self->{Str} += $str;
  $self->{MaxStr} += $str;
  $self->{Def} += $def;
  $self->{MaxDef} += $def;
  # Update technique proficency
  foreach (keys %{ $self->g("Techniques") }) {
    $self->{Techniques}{$_}{Success}++ unless $self->{Techniques}{$_}{Success} == 3;
  }
  signal("When", $self, "gainlevel", $self->{Level});
  return 1;
}

sub PRE_performtech {
  my $self = shift;
  # We're _totally_ UI man.
  my $tech = $Game->{UI}->selecttech;
  return -1 if $tech eq -1;
  # But can you carry it out? :P
  my $success = 0;
  $success = 33 if $Player->g("Techniques.$tech.Success") == 1;
  $success = 66 if $Player->g("Techniques.$tech.Success") == 2;
  $success = 99 if $Player->g("Techniques.$tech.Success") == 3;
  my $name = $Player->g("Techniques.$tech.Name");
  unless ( percent($success) ) {
    say "You fail to perform $name!";
    return (-42, "idle"); # The move still counts
  }
  # DELEGATE.
  return (-42, $name);
}

sub PRE_switchweapon {
  my $self = shift;
  # Get all the weapons, sorted by letter.
  my @weapons;
  if (%{ $self->g("Inv.Category.Weapons") }) {
    @weapons = map {
      $self->g("Inv")->get($_)
    } sort keys %{ $self->g("Inv.Category.Weapons") };
  } else {
    say "You don't even have any weapons!";
    return -1;
  }
  my $new;
  if (my $weapon = $self->g("Equipment.Weapon")) {
    # The first one that isn't $weapon
    foreach (@weapons) {
      next if $_->g("ID") == $weapon->g("ID");
      $new = $_;
      last;
    }
    unless ($new) {
      say "You have no other weapons to switch to!";
      return -1;
    }
  } else {
    $new = shift @weapons;
  }
  return (-42, "wield", $new);
}

sub PRE_lookmons {
  my $self = shift;
  say "There aren't any monsters around, but go ahead." unless keys %{ $Game->{Active} };
  $Game->{UI}->target;
  return -1;
}

sub PRE_debug {
  say "Do you really want to skip to the ending? (yn)";
  $Game->{UI}->msgrefresh;
  my $in = $Game->{UI}->prompt;
  if ($in eq "y") {
    # This is such a messy hack.
    foreach ($Player->{Z} + 1 .. 20) {
      $Game->{Levels}[$_] = {};
    }
    $Player->{Z} = 20;
    $Player->tile->{_} = ">";
    $Player->tile->{Stair} = 0;
    $Player->descend;
  }
  return -1;
}

sub PRE_help {
   $Game->{UI}->msgbox(1,
  "Movement is done with the vi/nethack keys: <Blue>hjklyubn",
  "<Blue>Control+P<black> should open up the message log.",
  "At a screen like this, only space will proceed. At prompts for items, letters   work. <Blue>?<black> will bring up a list of relevant items.",
  "<Blue>,<black> will take an item, <Blue>i<black> brings up inventory,
  <Blue>d<black> drops, <Blue>;<black> lists current items, <Blue>.<black>
  idles, <Blue>e<black> eats, <Blue>r<black> reads, <Blue>w<black> wields
  (weapons only), <Blue>W<black> wears (other equipment), <Blue>T<black>
  discards equipment, <Blue>><black> and <Blue><<black> descend or ascend,
  <Blue>v<black> lets you examine an item, <Blue>x<black> allows you to examine
  monsters, <Blue>a<black> lets you perform one of your special abilities (which  you'll learn every few levels), <Blue>f<black> fires a ranged weapon,
  and <Blue>Q<black> exits."
  );
  $Game->{UI}->msgbox(2);
  return -1;
}

define(PlayerChar => $pc, [
  "test", "msglog", "inv", "list", "redo", "test2", "examine", "die",
  "examinemons"
]);

42;
