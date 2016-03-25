##########
# Engine #
##########

package Roguelike::Engine;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::UI;
use Roguelike::PriorityQueue;
use Roguelike::Object;
use Cwd;

# Well, we need em, OK? Geez.

use Roguelike::Area;
use Roguelike::Area::Dungeon;
use Roguelike::Area::Cellular;
use Roguelike::Area::Tunnel;
use Roguelike::Area::Building;
use Roguelike::Area::Maze;

sub new {
  my $class = shift;
  my $queue = new Roguelike::PriorityQueue;
  my $self = bless {
    UI        => Roguelike::UI->select,
    Queue     => $queue,
    Actions   => {},
    Turns     => -1,
    Messages  => [],
    MsgLog    => [],
    Silence   => 0,
    Templates => {
      Obj => bless {
        # Default attributes of any objects
        Name     => "Unknown",
        Qty      => 1,
        Category => "Default",
        ID       => 0,
        InvName    => sub {
          # This is default for listing in inventory!
          my $self = shift;
          my $str = "";
          $str .= $self->g("Qty") . " " if $self->g("Qty") > 1;
          if ($self->g("Wieldable") or $self->g("Wearable")) {
            if ($self->g("Mod") >= 0) {
              $str .= "+" . $self->g("Mod") . " ";
            } else {
              $str .= "-" . $self->g("Mod") . " ";
            }
          }
          $str .= $self->g("Name");
          $str .= "s" if $self->g("Qty") > 1; # Whatever.
          if (defined $self->{Use}) {
            my $use = int((100 * $self->g("Use")) / $self->g("Durability"));
            $str .= " [$use%]";
          }
          $str .= " (wielded)" if $self->g("On") and $self->g("Category") eq
          "Weapons";
          $str .= " (worn)" if $self->g("On") and $self->g("Category") eq
          "Armour";
          return $str;
        }
      }, "Roguelike::Object"
    },
    Content => {},  # For stuff we load in
    Config => { # These're all defaults, naturally
      Category => {
        Projectiles => { Group => ["Mod", "Enchantment"] },
        Food          => { Group => ["Name"] },
        Scrolls       => { Group => ["Name"] },
        Potions       => { Group => ["Name"] },
        Weapons       => { Group => 0 },
        Armour        => { Group => 0 },
        Miscellaneous => { Group => ["Name"] },
        Default       => { Group => 0 },
      },
    },
    Random => {
      Queued => [],
      Used   => []
    },
    Levels => [],
    ItemPopulation => [],
    MonsterPopulation => [],
    MaxDepth => 1,  # The use for this is messy
    @_
  }, $class;
  push @{ $self->{IDs} }, $self->{Templates}{Object};
  return $self;
}

sub start {
  my $self = shift;
  # Set up delayed reactions and such
  $_->() foreach @{ $self->{DelayedInit} };
  $self->{UI}->refresh;
  $self->{UI}->msgrefresh;
  $self->{UI}->statrefresh;
  # Do per-game initialization stuff. The UI will provide a pretty menu
  # interface.
  $self->main;
}

sub main {
  # Everybody's initial priority is always 1 for now.
  my $self = shift;
  my $queue = $self->{Queue};
  $queue->add( pop @{ $Player->{Queue} } );
  if ($Player->g("Area.Monsters")) {
    $queue->add( pop @{ $_->{Queue} } ) foreach @{ $Player->g("Area.Monsters") };
  }
  while (1) {
    my $node = $queue->extract;
    unless ($node) {
      debug "No scheduled actions! Bug!";
    }
    my $mod = $node->{Priority};
    foreach ($node, @{$queue}) {
      $_->{Priority} -= $mod unless $_->{Priority} == 0;
      $_->{Energy} += $mod;
    }
    # Maybe *we* should handle energy calculations as far as factoring in
    # speed...
    if ($node->{Energy} < $node->{Cost}) {
      # Delay it.
      $queue->add({
        %{ $node },
        Priority => $node->{Cost} - $node->{Energy},
      });
    } else {
      my $return = $node->{Action}->();
      if ($node->{Type} == -42) {
        # It's a virus!
        $queue->add({
          %{ $node },
          Priority => $node->{OrigCost},
          Cost => $node->{OrigCost}
       }) if $return == -42;
      } else {
        $queue->add( shift @{ $node->{Actor}{Queue} } );
      }
    }
  }
}

sub save {
  my $self = shift;
  # File is hardcoded now! Haha. Overwritten, too. Nasty.
  my $path = "/home/dabreegster/perlrl/data";
  open SAVE, ">$path" or die "$path can't be modified! Gasp!";
  # Only thing we have to save so far is random numbers.
  print SAVE "$_\n" foreach @{ $Game->{Random}{Used} };
  close SAVE;
  return 1;
}

sub load {
  my $self = shift;
  # File is hardcoded now! Haha.
  my $path = "/home/dabreegster/perlrl/data";
  open LOAD, $path or return 0;
  # Only thing in there is random numbers.
  # Overwrite any in Queued.
  $Game->{Random}{Queued} = [];
  while (<LOAD>) {
    chomp($_);
    push @{ $Game->{Random}{Queued} }, $_;
  }
  close LOAD;
  say "[WARN] Random numbers loaded!";
  return 1;
}

sub addlevel {
  shift;
  my $map;
  my $populate;
  if ($_[0] =~ m/^</) {
    $populate = 0;
    $map = shift;
    $map =~ s/^<//;
    $map = loadmap($map);
    # loadmap will call populate() if necessary. Things might be fixed on the
    # external map!
  } else {
    $populate = 1;
    my $style = "Roguelike::Area::" . shift();
    $map = $style->generate(@_);
  }
  $map->{Monsters} ||= [];
  # Add the new level
  push @{ $Game->{Levels} }, $map;
  my $z = $#{ $Game->{Levels} };
  $map->{Depth} = $z;
  populate($map, 5) if $populate;
  # Are we level 0 though? Nothing above us.
  return $z if $z == 0;
  # Connect $z's up staircases to $z-1's down staircases
  my $cnt = 0;
  foreach (0 .. $#{ $map->{StairsUp} }) {
    $cnt = 0 if $cnt > $#{ $Game->{Levels}[-2]{StairsDown} };
    $map->{Map}[ $map->{StairsUp}[$_][0] ][ $map->{StairsUp}[$_][1]]{Stair} = $cnt;
    $cnt++;
  }
  $cnt = 0;
  foreach (0 .. $#{ $Game->{Levels}[-2]{StairsDown} }) {
    $cnt = 0 if $cnt > $#{ $map->{StairsUp} };
    $Game->{Levels}[-2]{Map}[ $Game->{Levels}[-2]{StairsDown}[$_][0] ][ $Game->{Levels}[-2]{StairsDown}[$_][1] ]{Stair} = $cnt;
    $cnt++;
  }
  return $z;
}

sub parsecontent {
  my $self = shift;
  # Hardcoding, WHATEVER
  my $path = getcwd . "/" . shift;
  # First load and parse the data.
  my $entries = {};
  open LOAD, $path or die "Can't open $path! $!";
  my $current = -1;
  my $multi = -1;  # string of key otherwise. so far just Desc or an attack.
  my $attack = 0; # Nay I say
  my $event = -1;
  while (<LOAD>) {
    chomp($_);
    my $line = $_;
    if ($attack) {
      # Sadly, we have to have indentation at the start of the line.
      next if $line =~ m/^#/;
      if ($line =~ m/^\s+/) {
        $line =~ s/^\s+//;
        if ($multi eq "-1") {
          $line =~ m/^([\w\s\(\)]+): <\(/;
          $multi = $1;
          # TP?
          if ($multi =~ s/ \((\d+)\)$//) {
            $current->{Attacks}{$multi}{TP} = $1;
          }
          $current->{Attacks}{$multi}{Action} = "";
          next;
        } else {
          next unless $line;
          next if $line =~ m/^#/;
          # Finished?
          if ($line eq ")>") {
            $multi = -1;
            next;
          } else {
            # More code.
            $current->{Attacks}{$multi}{Action} .= " $line";
            next;
          }
        }
      } else {
        $attack = 0;
        $multi = -1;
      }
    }
    if ($event ne "-1") {
      $line =~ s/^\s+//;
      next unless $line;
      next if $line =~ m/^#/;
      # Finished?
      if ($line eq ")>") {
        $event = -1;
        next;
      } else {
        # More code.
        $current->{$event}{Action} .= " $line";
        next;
      }
    }
    if ($multi ne "-1") {
      next if $line =~ m/^#/;
      # Finished YET?
      unless ($line =~ m/^\w+:/) {
        $line =~ s/^\s+//;
        $current->{$multi} .= " $line";
        next;
      }
      $multi = -1;
    }
    # So what've we got here?
    next unless $line;
    next if $line =~ m/^#/;
    # Assume the file doesn't have stupid syntax things like </> outside a
    # definition
    if ($line =~ m/^<new (\w+)>$/) {
      $current = { Attacks => {} };
      $line =~ s/^<new (\w+)>$/$1/;
      $current->{Base} = $line;
    }
    if ($line =~ m/<\/>/) {
      $entries->{ $current->{Name} } = $current;
      $current = -1;
      next;
    }
    # Are we the start of an event? Whew...
    if ($line =~ m/^{/) {
      # Get the event string and optional flags
      $line =~ s/^{([\w\s,]+)}//;
      $event = $1;
      $current->{$event} = {};
      $line =~ m/\(([^\)]+)\): <\($/;
      my $flags = $1;
      foreach my $config (split(/, /, $flags)) {
        my ($var, $val) = split(/=/, $config);
        $current->{$event}{$var} = $val;
      }
      next;
    }
    # OK, we're a data property of some sort then.
    $line =~ s/^(\w+):\s*//;
    if ($1 eq "Attacks") {
      $attack = 1;
      next;
    }
    if ($1 eq "Init") {
      $event = $1;
      $current->{$event} = {};
      next;
    }
    if ($1 eq "Behavior") {
      $event = $1;
      $current->{$event} = {};
      next;
    }
    $current->{$1} = $line;
    # Are we about to enter multiline mode?
    $multi = $1 if $1 eq "Desc";
  }
  close LOAD;
  return $entries;
}

sub loadmons {
  my $self = shift;
  my $monsters = $Game->parsecontent( shift() );
  # Translate into actual objects...
  my @monsters;
  foreach my $dat (values %{ $monsters }) {
    my $char = $Game->{Templates}{ $dat->{Base} }->new(
      Name => $dat->{Name},
      Desc => $dat->{Desc},
      Rank => defined $dat->{Rank} ? $dat->{Rank} : undef,
    );
    ($char->{Color}, $char->{Symbol}) = split(/ /, $dat->{Symbol});
    foreach my $stat (qw( Str Def HP TP Exp )) {
      next unless $dat->{$stat};
      if ($dat->{$stat} =~ m/^\d+$/) {
        $char->{$stat} = $dat->{$stat};
      } else {
        $dat->{$stat} =~ m/^(\d+)[.\s,]+(\d+)$/;
        $char->{$stat} = [$1, $2];
      }
    }
    # Now eval its attacks.
    while ((my $name, my $str) = each %{ $dat->{Attacks} }) {
      $char->{Attacks}{$name}{TP} = $str->{TP} || 0;
      $str = "sub { $str->{Action} }";
      $char->{Attacks}{$name}{Action} = eval $str or debug $@;
    }
    # Event reactions! Kinda messy...
    foreach my $key (keys %$dat) {
      next unless $key =~ m/^(Before|After|When)/;
      my $react = eval "sub { $dat->{$key}{Action} }";
      delete $dat->{$key}{Action};
      push @{ $self->{DelayedInit} }, sub {
        $char->react(
          to => [ split(/, /, $key) ],
          by => $react,
          %{ $dat->{$key} }
        );
      };
    }
    # Init?
    if ($dat->{Init}) {
      $char->{Init} = eval "sub { $dat->{Init}{Action} }" or debug $@;
    }
    # Behavior?
    if ($dat->{Behavior}) {
      $char->{Behavior} = eval "sub { $dat->{Behavior}{Action} }" or debug $@;
    }
    # Lastly, set it up with some equipment.
    # We have to actually parse it first. Sucks.
    $char->{Wearing} = [];
    foreach (split(/, /, $dat->{Equipment})) {
      if (m/^(.+) \((\w+)\)/) {
        push @{ $char->{Wearing} }, [$Game->{Content}{$1}, $2];
      } else {
        push @{ $char->{Wearing} }, $Game->{Content}{$1};
      }
    }
    $Game->{Content}{ $char->g("Name") } = $char;
    if ($dat->{Base} eq "PlayerChar") {
      $Player = $char;
      # This is a FUGLAY hack
      $Game->{Silence} = 1;
      $Game->{Templates}{Character}{Init}->($char);
      $Game->{Silence} = 0;
    } else {
      push @monsters, $char;
    }
  }
  # Its position in the population list depends upon Rank
  push @{ $Game->{MonsterPopulation} }, @monsters;
  return @monsters;
}

sub loaditems {
  my $self = shift;
  my $dat = $Game->parsecontent( shift() );
  # Translate into actual objects...
  my @items;
  foreach my $dat (values %{ $dat }) {
    my $item = $Game->{Templates}{ $dat->{Base} }->new(
      Name => $dat->{Name},
      Desc => $dat->{Desc},
      Durability => defined $dat->{Durability} ? $dat->{Durability} : undef,
      Power => defined $dat->{Power} ? $dat->{Power} : undef,
      Rank => defined $dat->{Rank} ? $dat->{Rank} : undef,
      MaxMod => defined $dat->{MaxMod} ? $dat->{MaxMod} : undef,
      Category => defined $dat->{Category} ? $dat->{Category} : undef,
      Wieldable => defined $dat->{Wieldable} ? $dat->{Wieldable} : undef,
      Readable => defined $dat->{Readable} ? $dat->{Readable} : undef,
      Fits => defined $dat->{Fits} ? [split(/, /, $dat->{Fits})] : undef,
      Ranged => defined $dat->{Ranged} ? $dat->{Ranged} : undef,
    );
    ($item->{Color}, $item->{Symbol}) = split(/ /, $dat->{Symbol});
    # Event reactions! Kinda messy...
    foreach my $key (keys %$dat) {
      next unless $key =~ m/^(Before|After|When)/;
      my $react = eval "sub { $dat->{$key}{Action} }" or debug $@;
      delete $dat->{$key}{Action};
      push @{ $self->{DelayedInit} }, sub {
        $item->react(
          to => [ split(/, /, $key) ],
          by => $react,
          %{ $dat->{$key} }
        );
      };
    }
    # Init?
    if ($dat->{Init}) {
      $item->{Init} = eval "sub { $dat->{Init}{Action} }" or debug $@;
    }
    # Behavior?
    if ($dat->{Behavior}) {
      $item->{Behavior} = eval "sub { $dat->{Behavior}{Action} }" or debug $@;
    }
    push @items, $item;
    $Game->{Content}{ $item->g("Name") } = $item;
  }
  # Its position in the population list depends upon Rank
  push @{ $Game->{ItemPopulation} }, @items;
  return @items;
}

sub loadkeymap {
  my $self = shift;
  # Hardcoding, WHATEVER
  my $path = getcwd . "/" . shift;
  open LOAD, $path or die "Can't open $path! $!";
  while (<LOAD>) {
    chomp($_);
    my $line = $_;
    $line =~ m/^(.+):(.+)$/;
    my ($key, $action) = ($1, $2);
    $action =~ s/\s+//g;
    if ($Game->{UI}{Keymap}{$key}) {
      debug "Key $key remapped from $Game->{UI}{Keymap}{$key} to $action!";
    }
    $Game->{UI}{Keymap}{$key} = $action;
  }
  close LOAD;
  return 1;
}

42;
