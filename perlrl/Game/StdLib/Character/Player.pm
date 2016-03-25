package Game::StdLib::Character::Player;

use strict;
use warnings;
use Util;

use BDSM::Map;

use base "Game::StdLib::Character";
__PACKAGE__->announce("Player");

__PACKAGE__->classdat(
  Unique   => 1,  # TODO so chars that dont have this..
  StatList => [qw(HP ESM Str Def Dext)],
  LightSrc => 5 # Shrug
);

# We're about as special as ya can get
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts, stats => ["ESM", "Str"]);
  # Can't really beat the order.. our stats are made after we join the map, so the timers
  # aren't started right.
  $self->{Map}->join($self) if $self->{Map};

  $self->{Exp} = $self->{ExpWorth} = 0;
  $self->_construct(\%opts => "ExpCurve", "Gender");
  $self->{Delay} = 0;
  $self->{Journal} = {};

  $self->{Fighting} = -1;
  $self->{CloseAttack} = "weapon";
  $self->{RangeAttack} = "fireweapon";

  return $self;
}

# Pretty-print, plox
sub id {
  my $self = shift;
  my $name = $self->Name;
  return $self->type . "_${name}_$self->{ID}";
}

# List our inventory
sub lsinv {
  my ($self, $opts, @cats) = args @_;
  if (@cats) {
    # Make sure the categories specified have something in them.
    @cats = grep { $self->{Inv}{Category}{$_} } @cats;
  } else {
    @cats = (keys %{ $self->{Inv}{Category} });
  }
  unless (@cats) {
    msg err => "Sorry, you don't <white>HAVE<Red> anything!";
    return;
  }

  my @lines = ("Inventory");
  push @lines, "<cyan>Type an item's letter to examine it.",
               "<cyan>You have affinity with highlighted items, meaning you can use them
                effectively" if $opts->{examine};
  
  foreach my $cat (@cats) {
    push @lines, $cat;
    foreach my $item ($self->{Inv}->all($cat)) {
      push @lines, $item->name("inv");
    }
  }
  unshift @lines, "-size", ["100%", "100%"] if $opts->{full};
  if ($opts->{examine}) {
    while (1) {
      my $key = UI->popup(@lines);
      if (my $item = $self->{Inv}->get($key)) {
        UI->popup("-size", ["100%", "100%"], $item->describe);
      } else {
        last;
      }
    }
  } else {
    return UI->popup(@lines);
  }
}

# Grab something from our inventory
sub selectinv {
  my ($self, $query, $categories, $otherkeys) = @_;
  my %otherkeys = map { $_ => 1 } @$otherkeys;
  
  UI->start_in;
  
  my $return;
  while (1) {
    msg err => $query;
    my $in = UI->wait_input;
    if ($in eq "<ESCAPE>" or $in eq " ") {
      msg err => "Never mind.";
      last;
    } elsif ($in eq "?") {
      $in = $self->lsinv(@$categories);
      last unless $in;  # We don't have anything. ^^
    } elsif ($otherkeys{$in}) {
      $return = $in;
      last;
    }
    if (my $item = $self->{Inv}->get($in)) {
      $return = $item;
      last;
    } else {
      msg err => "You don't have that.";
    }
  }                                                                       
  UI->stop_in;                                                    
  return $return;
}

# Are we THE player?
sub player {
  my $self = shift;
  return unless Player;
  return $self->{ID} == Player->{ID};
}

# To actually enforce it, easier to keep track of when we can next do something
sub lag {
  my ($self, $lag) = @_;
  if ($self->player) {
    GAME->{Countdown} = $lag;
    $self->{Lag} = $lag + time;
  } else {
    $self->{Lag} = $lag;
  }
}

###########################################################################################

sub ON_gainexp {
  my ($self, $heap, $xp) = actargs @_;
  $self->{Exp} += $xp;

  my $up = 0;
  while ($self->{Exp} >= $self->nextexp) {
    $self->{Exp} -= $self->nextexp;
    $up++;
    # Level up!
    $self->{Level}++;

    # Increase stats
    if (GAME->fullsim) {
      foreach my $stat (qw(HP Str Def Dext ESM)) {
        my $now = $self->{$stat}{Cap};
        my $add;
        if ($stat eq "HP" or $stat eq "ESM") {
          $add = random(0, $self->Stats($stat) * CFG->{Scale}{$stat});
        } else {
          $add = random(0, $self->Stats($stat));
        }
        $self->{$stat}->change($now + $add);
        $self->{$stat}->mod($self->{$stat}{Cap}) unless $stat eq "HP" or $stat eq "ESM";
      }
    }

    $self->_moveset;

    $self->saymsg("[subj] levels up to $self->{Level}");
  }
}

###########################################################################################

sub PRE_lstile {
  my ($self, $heap, $explicit) = actargs @_;

  my $stair = $self->tile->{Stair} // [];
  my $z = ref $stair ? $stair->[0] : $stair;  # TODO technically fullsim is arrayref but..
  if ($z and $z !~ m/^\d+$/) {
    msg see => "There is a staircase leading to $z.";
  } elsif ($self->tile->{_} eq "<") {
    msg see => "There is a staircase leading up.";
  } elsif ($self->tile->{_} eq ">") {
    msg see => "There is a staircase leading down.";
  }
  my @ls = $self->{Map}->inv($self->{Y}, $self->{X}, "all");
  if (@ls == 1) {
    msg see => "You see here " . $ls[0]->name("general") . ".";
  } elsif (@ls > 1) {
    msg see => "You see here:";
    foreach (@ls) {
      msg see => $_->name("general");
    }
  } else {
    msg see => "There's nothing here." if $explicit;
  }

  return STOP;
}

###########################################################################################

sub PRE_take {
  my ($self, $heap) = actargs @_;

  my @ls = $self->{Map}->inv($self->{Y}, $self->{X}, "all");
  my @get;
  if (@ls == 0) {
    return STOP($self, "There's nothing here!");
  } elsif (@ls == 1) {
    @get = @ls;
  } else {
    UI->start_in;
    msg see => "There are " . scalar @ls . " items here:";
    my $all = 0;  # Get the rest?
    foreach my $obj (@ls) {
      push(@get, $obj), next if $all;
      $obj->saymsg("Pick up [the 0]? (y,n,a,q)");
      my $in = UI->wait_input;
      last if $in eq "q";
      @get = (), last if $in eq " " or $in eq "<ESCAPE>";
      next if $in eq "n";
      $all = 1 if $in eq "a";
      push @get, $obj if $in eq "y" or $all;
    }
    UI->stop_in;
    unless (@get) {
      return STOP($self, "None of it was worth it anyway.");
    }
  }
  $heap->{Args} = [@get];
}

sub AFTER_take {
  my ($self, $heap, @items) = actargs @_;
  return unless $self->player;
  foreach my $item (@items) {
    msg see => $item->name("inv");
  }
}

###########################################################################################

sub PRE_drop {
  my ($self, $heap) = actargs @_;

  return STOP unless my $item = $self->selectinv("Drop what? (? to list)");
  $heap->{Args} = [$item];
}

###########################################################################################

sub PRE_changedepth {
  my ($self, $heap, $dir) = actargs @_;
  my $tile = $self->tile;
  return STOP($self, "There's no staircase here!") unless $tile->{_} eq ">" or $tile->{_} eq "<" or $tile->{HotelRm};
}

###########################################################################################

sub PRE_inv {
  my ($self, $heap) = actargs @_;
  $self->lsinv(-full => 1, -examine => 1);
  return STOP;
}

###########################################################################################

sub PRE_wield {
  my ($self, $heap) = actargs @_;

  return STOP unless my $item = $self->selectinv("Wield what? (- for none)", ["Weapons"], ["-"]);
  if ($item eq "-") {
    if ($item = $self->{Equipment}{Weapon}) {
      return REDIRECT("unequip", $item);
    } else {
      return STOP($self, "You aren't wielding anything!");
    }
  }

  return REDIRECT("equip", $item, "Weapon");
}

###########################################################################################

sub PRE_quickwield {
  my $self = shift;

  my @weapons = $self->{Inv}->all("Weapons");
  return STOP($self, "You have no weapons!") unless @weapons;
  
  my $wieldme;
  if (my $current = $self->{Equipment}{Weapon}) {
    # Already got a weapon, so find the first one in here that isn't us
    foreach (@weapons) {
      next if $_->{ID} == $current->{ID};
      $wieldme = $_;
      last;
    }
    return STOP($self, "You have no other weapons to wield!") unless $wieldme;
  } else {
    $wieldme = shift @weapons;
  }
  return REDIRECT("equip", $wieldme, "Weapon");
}

###########################################################################################

sub PRE_wear {
  my $self = shift;

  return STOP unless my $item = $self->selectinv("Wear what?", ["Masks"]);

  # It's pointless to find a slot if we're already wearing it. So steal that check from
  # Character's BEFORE_equip.
  return STOP($self, "You're already wearing [1]!", $item) if $item->{On};

  # So find a slot for it.
  return STOP($self, "You can't wear [1]!", $item) unless $item->Fits;
  my (@free, @filled);
  foreach ($item->Fits) {
    $self->{Equipment}{$_} ? push(@filled, $_) : push(@free, $_);
  }

  # If we have 1 free slot, fill it automatically.
  # But otherwise, let em choose from all the slots.
  my $slot;
  if (@free == 1) {
    $slot = shift @free;
  } else {
    my @slots;
    push @slots, "$_ (available)" foreach @free;
    push @slots, "$_ (filled)" foreach @filled;
    $slot = UI->choose(
      "Where do you want to wear " . $item->name("specific") . "?", @slots
    );
    $slot =~ s/ \(.+$//;
  }
  return REDIRECT("equip", $item, $slot);
}

###########################################################################################

sub PRE_takeoff {
  my $self = shift;

  return STOP unless my $item = $self->selectinv("Take what off?", ["Masks"]);
  return REDIRECT("unequip", $item);
}

###########################################################################################

sub PRE_use {
  my ($self, $heap) = actargs @_;

  return STOP unless my $item = $self->selectinv("Use what? (? to list)");
  $heap->{Args} = [$item];
}

###########################################################################################

sub AFTER_death {
  my ($self, $heap) = actargs @_;
  
  if ($self->player) {
    UI->popup("Oops, you died. Sorry.");
    exit;
  } else {
    $self->saymsg("[subj] died. So long, sucka!");
  }
}

###########################################################################################

# Because we do the checks here, the fire attack has no Check since it's pretty player and
# UI-exclusive.
sub PRE_fire {
  my ($self, $heap) = actargs @_;
  my $atk = $self->{RangeAttack};
  return REDIRECT("attack", $self->{RangeAttack});
}

###########################################################################################

sub PRE_explore {
  my ($self, $heap) = actargs @_;
  UI->{Main}->target(
    -ref    => $self,
    -scroll => 1,
    -call   => sub {
      my ($map, $y, $x, $key) = @_;
      my $target = $map->get($y, $x);
      if (ref $target) {
        $target = $target->{Aggregate} if $target->{Aggregate};
        $key eq "?" ?
          UI->popup($target->describe) : msg see => ucfirst "@{[$target->name('general')]}. Press ? to see it!";
      } else {
        msg see => "Tile $target. At $y, $x.";
        my $tile = $map->tile($y, $x);
        while (my ($from, $scent) = each %{ $tile->{Scents} }) {
          msg see => "  <blue>$from = $scent";
        }
      }
    }
  );
  UI->{Main}->focus;
  return STOP;
}

###########################################################################################

sub PRE_ability {
  my ($self, $heap) = actargs @_;

  my @ls;
  foreach my $set (values %{ $self->{Moveset} }) {
    foreach (@$set) {
      my $atk = $self->Attacks("$_");
      next if $atk->{Name} eq "fireweapon" or $atk->{Name} eq "weapon";
      push @ls, $atk;
    }
  }

  return STOP($self, "You don't know how to do anything yet!") unless @ls;
  # TODO: line up in columns
  my $num = UI->choose(-idx => 1, "Perform what ability?",
    "Never mind",
    map { "$_->{Name} ($_->{ESMCost}) - $_->{Descr}" } @ls
  );
  return STOP unless $num;
  return REDIRECT("attack", $ls[$num - 1]->{Name});
}

###########################################################################################

sub PRE_devmode {
  my ($self, $heap) = actargs @_;

  my $do = UI->choose(-idx => 1, -escapable => 1, "Yes, my liege?",
    "Let there be light",
    "Spawn a monster (to your right)",
    "Spawn an item (to your right)",
    "Cyphen<->Uben",
    "Level up",
    "List timers",
    "Save this map",
    "Draw next chunk"
  ) // return STOP;
  if ($do == 0) {
    my $map = GAME->{Map};
    foreach my $y (0 .. $map->height) {
      foreach my $x (0 .. $map->width) {
        $map->tile($y, $x)->{Lit} ||= 1;
        $map->modded($y, $x);
      }
    }
    UI->{Main}->drawme;
    return STOP;
  } elsif ($do == 1) {
    my %reverse = reverse %{ GAME->{Templates} };
    my @ls = map { $reverse{$_} } @{ GAME->{Baddies} };
    $heap->{Args} = ["char", UI->choose("Spawn what?", sort @ls)];
  } elsif ($do == 2) {
    my %reverse = reverse %{ GAME->{Templates} };
    my @ls = map { $reverse{$_} } @{ GAME->{Stuff} };
    $heap->{Args} = ["item", UI->choose("Spawn what?", sort @ls)];
  } elsif ($do == 3) {
    $heap->{Args} = ["transition"];
  } elsif ($do == 4) {
    $heap->{Args} = ["levelup"];
  } elsif ($do == 5) {
    $heap->{Args} = ["timers"];
  } elsif ($do == 6) {
    return STOP unless UI->choose("This'll overwrite ingame.map in saved_maps.", "Alright", "NOOO WAAAIT") eq "Alright";
    open my $out, ">../saved_maps/ingame.map" or return STOP($self, "Can't >ingame.map: $!");
    print $out $self->{Map}->_savemap;
    close $out;
    return STOP;
  } elsif ($do == 7) {
    $self->{Map}->drawnext;
    UI->{Main}->drawme;
    return STOP;
  } else {
    return STOP;
  }
}

sub BEFORE_devmode {
  my ($self, $heap, $cmd, @args) = actargs @_;
  if ($cmd eq "item") {
    my $y = $self->{Y};
    my $x = $self->{X} + 1;
    my $new = GAME->make($args[0]);
    $self->{Map}->inv($y, $x, "add", $new);
    $heap->{Made} = [$new, $y, $x]; # TODO hope we never send all a heap ;)
  } elsif ($cmd eq "char") {
    my $y = $self->{Y};
    my $x = $self->{X} + 1;
    my $new = GAME->make($args[0],
      Map => $self->{Map}, At => [$y, $x], DontShare => 1
    );
    delete $new->{DontShare}; # TODO ehhh
    $heap->{Made} = [$new];
  } elsif ($cmd eq "transition") {
    return STOP($self, "Not there...") unless $self->{Map}{Depth} eq "Cyphen";
    $self->{Map}->script("Transition", $self);
  } elsif ($cmd eq "levelup") {
    return REDIRECT("gainexp", $self->nextexp);
  } elsif ($cmd eq "timers") {
    debug [keys %{ GAME->{Timers} }];
  }
}

sub ON_devmode {
  my ($self, $heap, $cmd, @args) = actargs @_;
}

###########################################################################################

# Display messages fullscreen
sub PRE_msglog {
  my ($self, $heap) = actargs @_;
  UI->popup(
    -size => ["100%", "100%"],
    -start => "bottom",
    "<Black/white>Message Log", UI->{Msgs}->all
  );
  return STOP;
}

###########################################################################################

sub PRE_help {
  my ($self, $heap) = actargs @_;
  my @keys;
  # TODO: printing <KEY_DOWN> and not color tag!
  while (my ($key, $cmd) = each %{ UI->{_Keymap}{Commands} }) {
    next if $key =~ m/<.+>/;
    push @keys, "$key = $cmd";
  }
  UI->popup(
    -size => ["80%", "50%"],
    #-at   => [0, 0],
    "<Red/white>Help!",
    "This is just the current keymap. You can edit Keymap, if you haven't figured that out
     yet.",
     "Press tab to switch between chat and game.",
     "",
     @keys
  );
  return STOP;
}

###########################################################################################

sub PRE_defaultclose {
  my ($self, $heap) = actargs @_;
  my @ls = @{ $self->{Moveset}{adj} };
  my $num = UI->choose(-idx => 1,
    "Select the default ability to perform when you bump into something.",
    "Never mind (keep current <white>$self->{CloseAttack}<grey>)",
    @ls
  );
  $self->{CloseAttack} = $ls[$num - 1];
  return STOP;
}

###########################################################################################

sub PRE_defaultrange {
  my ($self, $heap) = actargs @_;
  my @ls = (@{ $self->{Moveset}{fire} }, @{ $self->{Moveset}{beam} }, @{ $self->{Moveset}{area} });
  my $num = UI->choose(-idx => 1,
    "Select the default ability to perform when you attempt a ranged attack.",
    "Never mind (keep current <white>$self->{RangeAttack}<grey>)",
    @ls
  );
  $self->{RangeAttack} = $ls[$num - 1];
  return STOP;
}

###########################################################################################

sub PRE_autoexplore {
  my ($self, $heap) = actargs @_;

  # Whoa, don't start if there's stuff nearby...
  unless ($heap->{findonly}) {  # the on_screen triggers will catch this.
    foreach (values %{ UI->{Main}{OnScreen} }) {
      next unless ref($_) =~ m/::/ and $_->is("Monster");
      # It's on screen, but is it in our FOV?
      next unless $_->tile->{Lit} == 2;
      return STOP($self, "There's a monster nearby, so you can't explore safely.");
    }
  }
  
  my @path;
  unless ($self->{Map}{_Data}{superlight}) {
    @path = $self->{Map}->floodfind($self->{Y}, $self->{X}, Lit => 0);
  }
  unless (@path) {
    delete $self->{Explore};
    return STOP($self, "You've explored all of the map already!");
  }
  $self->{Explore} = \@path;
  return STOP if $heap->{findonly};  # Timer is already scheduled.
  msg err => "Press any key to stop exploring.";  # TODO
  $self->schedule(
    -do    => sub {
      unless (@{ $self->{Explore} }) {
        $self->autoexplore(-findonly => 1, -stages => ["Pre"]);
        return "STOP" unless @{ $self->{Explore} };
      }
      GAME->goodcmd_cb($self, { Action => "go", Args => shift @{ $self->{Explore} } });
      #return (CFG->{Scale}{Speed_Max} - $self->Speed + 1) * CFG->{Scale}{Speed}; # TODO
      return $self->{Map}{_Data}{mvlag} // 0;
    },
    -tags  => ["explore", "map"],
    -id    => "explore_$self->{ID}",
  );
  return STOP;
}

###########################################################################################

sub PRE_journal {}  # Just exist to be a valid player action

sub BEFORE_journal {
  my ($self, $heap) = actargs @_;
  @{ $heap->{Args} } = keys %{ $self->{Journal} };
  return STOP($self, "You don't have any journal entries yet; go explore!") unless @{ $heap->{Args} };
}

###########################################################################################

sub PRE_attack {
  my ($self, $heap, $attack) = actargs @_;

  $attack = $self->Attacks($attack);

  # Some things we just need to do early.. fullsim will repeat them, but oh well.
  if ($attack->{ESMCost}) {
    return STOP($self, "You don't have enough ESM to $attack->{Name}!")
      if $self->{ESM}->value < $attack->{ESMCost};
  }
  if ($attack->{Check}) {
    my $code = $attack->{Check}->($self);
    return STOP if $code and $code eq ":STOP";
  }

  my @code;
  if (ref $attack->{UI} eq "CODE") {
    @code = $attack->{UI}->($self);
  } elsif ($attack->{Range}[0] =~ m/(fire|beam|area)/) {
    my $r = $attack->{Range}[1]; $r = $r->($self) if ref $r eq "CODE";
    my $draw = $attack->{Draw};  $draw = $draw->($self) if ref $draw eq "CODE";
    # Choose a target in range.
    @code = UI->{Main}->target(
      -ref        => $self,
      -call       => sub {
        my ($map, $y, $x, $key) = @_;
        my $target = $map->get($y, $x);
        return unless ref $target;
        msg see => "Fire at " . $target->name . "?";
      },
      -range      => $r,
      -projectile => $draw,
      -no_self    => 1
    );
    @code = STOP($self, "[subj] can't fire at themself!")
      if $code[0] == $self->{Y} and $code[1] == $self->{X};
  }
  return @code if @code and $code[0] eq ":STOP";

  $heap->{Args} = [$attack->{Name}, @code];
}

###########################################################################################

sub PRE_heal {}

sub ON_heal {
  my ($self, $heap) = actargs @_;
  $self->{HP}->mod($self->{HP}->cap);
}

###########################################################################################

sub ON_idle {
  my ($self, $heap) = @_;
  $self->lag(1);
}

###########################################################################################

sub PRE_interact {}

42;
