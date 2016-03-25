package Game::StdLib::Character;

use strict;
use warnings;
use Util;

use Game::Container;
use Game::Stat;
use Game::Attack;

use base "BDSM::Agent";
__PACKAGE__->announce("Character");

__PACKAGE__->classdat(
  Wielding      => "",
  Wearing       => [],
  Carrying      => [],
  StatList      => [qw(HP Def Dext)],
  Unique        => 0,
  player        => 0, # Questionable, almost.
  human_control => 0
);

# We don't just move, we do stuff!
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);
  $self->_construct(\%opts => "_Stats", "Level", "Wielding", "Wearing", "Carrying");
  $self->{Level} ||= 1;

  $self->{Inv} = Game::Container->new($self);

  # Equip our shit
  $self->{Equipment} = {};
  if (my $wield = $self->Wielding) {
    # Pass in type name or instance
    unless (ref $wield) {
      $wield = GAME->make($wield, OOD => 0);
    }
    $self->{Inv}->add($wield);
    $self->equip($wield, "Weapon");
  }

  foreach ($self->Wearing) {
    # TODO: whip out the Pre logic to autoselect slot? actually make a new fxn both use
  #  #$self->equip(@$_);
  }

  foreach my $make ($self->Carrying) {
    my ($type, @args) = @$make;
    my $item = GAME->make($type, OOD => 0, @args);
    $self->{Inv}->add($item);
  }

  # Create our stats.
  $opts{stats} ||= [];
  foreach my $stat ($self->StatList) {
    last unless GAME->fullsim;
    my @rate;
    my $base;
    if (CFG->{Scale}{"${stat}_Rate"}) {
      @rate = (RestoreRate => (CFG->{Scale}{"${stat}_Rate_Max"} - $self->Stats("${stat}_Rate") + 1) * CFG->{Scale}{"${stat}_Rate"});
      $base = $self->{Level} * $self->Stats($stat) * CFG->{Scale}{$stat};
    } else {
      $base = $self->Stats($stat) * CFG->{Scale}{$stat} + ($self->{Level} - 1) * $self->Stats($stat);
    }
    $self->{$stat} = Game::Stat->new(
      Max         => random($base - CFG->{Scale}{StatDeviance}, $base + CFG->{Scale}{StatDeviance}),
      Owner       => $self,
      Name        => $stat,
      @rate
    );
  }

  $self->{ACMod} = $self->{EVMod} = 0;
  $self->_moveset;

  return $self;
}

# Compile a moveset
sub _moveset {
  my $self = shift;
  $self->{Moveset} = {
    adj => [], FOV => [], fire => [], beam => [], area => [], custom => []
  };
  foreach my $attack ($self->merge_classdat("Attacks")) {
    next unless ref $attack;  # We're looping over a hash, keys and all.
    # no weapon attacks for them by default
    next if $self->is("Monster") and $attack->{Name} eq "weapon" or $attack->{Name} eq "fireweapon";
    if ($attack->{LearnAt}) {
      next if $self->{Level} < $attack->{LearnAt};
      $self->saymsg("[subj] learns $attack->{Name}!")
      if $self->player and $attack->{LearnAt} == $self->{Level};
    }
    push @{ $self->{Moveset}{ $attack->{Range}[0] } }, $attack->{Name};
  }
}

# Do we have the object in our inventory?
sub has {
  my ($self, $item) = @_;
  return $item->{Owner} == $self->{Inv};
}

# Pack ourselves up to breathe again elsewheres
sub serialize {
  my $self = shift;

  # Do a shallow copy of the sprite's data.
  my $send = bless { %$self }, ref $self;
  delete $send->{$_} for qw(Goal Aggregate Sprite Map Equipment Attacks);

  $send->{Inv} = [ map { $_->serialize } $self->{Inv}->all ];

  return $send;
}

sub unserialize {
  my ($self, $map) = @_;
  $self->{Map} = $map;
  $map->join($self);
  $self->{Aggregate} = $self->{Sprite} = $self;
  my $inv = Game::Container->new($self);
  foreach my $item (@{ $self->{Inv} }) {
    $inv->_client_add( $item->recreate() );
    $self->{Equipment}{ $item->{On} } = $item if $item->{On}
  }
  $self->{Inv} = $inv;

  # TODO inject another unserialize that calls this one and yeah.
  if ($self->{ClientID} and GAME->{ClientID} == $self->{ClientID}) {
    # We're the Player!
    GAME->{Player} = $self;
  }
}

# Take damage
sub ouch {
  my ($self, $damage, $killer) = @_;

  $self->{HP}->mod($self->{HP}->value - int $damage);
  if ($self->{HP}->value <= 0) {
    $self->death($killer);
    return 1;
  }
  return;
}

# On aisle three, no less
sub cleanup {
  my $self = shift;
  $self->_blitoff;
  $self->{Map}->quit($self);
  GAME->unschedule(-actor => $self);
  GAME->unschedule(-tags => ["stat_$self->{ID}"]);
  delete GAME->{Objects}[ $self->{ID} ];
  delete GAME->{Objects}[ $_->{ID} ] foreach $self->{Inv}->all;
  $self->fxn("WhenCleanup");
}

# Script an actor's movements!
sub trekpath {
  my ($self, $file) = @_;
  my $script =  slurp($file);
  my $VAR1;
  eval $script;
  $self->{Path} = $VAR1;
  $self->schedule(-do => "_followpath", -id => "follow_$self->{ID}", -tags => ["map"]);
}

sub _followpath {
  my $self = shift;
  $self->go(@{ shift @{ $self->{Path} } });
  return @{ $self->{Path} } ? shift @{ $self->{Path} } : "STOP";
}

sub describe {
  my $self = shift;
  my @lines;
  push @lines, $self->Name . " (ID $self->{ID})";
  push @lines, $self->Descr;

  push @lines, "$_: " . $self->{$_}->value for $self->StatList;
  my @extra = $self->fxn("WhenDescribe");
  push @lines, @extra unless $extra[0] eq ":NOTHING";
  push @lines, "level, exp, equipment...";
  return @lines;
}

# After doing something, lag.
sub lag {
  my ($self, $lag) = @_;
  $self->{Lag} = $lag;
}

sub name {
  # TODO modifiers.. angry, berserk?
  my ($self, $style) = @_;
  $style ||= "general";
  my $name = $self->Name;
  if ($style eq "general") {
    return $name if $self->Unique;
    return $name =~ m/^(a|e|i|o|u)/ ? "an $name" : "a $name";
  } elsif ($style eq "specific") {
    # TODO: doesnt work?
    return $name if $self->Unique;
    return "the $name";
  } elsif ($style eq "possessive") {
    return $self->name("specific") . "'s";
  }
}

# We want it. Now. From our inventory.
sub findinv {
  my ($self, $type) = @_;
  my @match;
  foreach ($self->{Inv}->all) {
    push @match, $_ if $_->is($type);
  }
  return @match;
}

###########################################################################################

sub BEFORE_take {
  my ($self, $heap, @items) = actargs @_;
  foreach (@items) {
    next if $_->is("Item");
    return STOP($self, $_->id . " isn't an item!");
  }
}

sub ON_take {
  my ($self, $heap, @items) = actargs @_;

  my $cnt = 0;
  foreach my $item (@items) {
    $item->{Owner}->del($item);     # Get off the tile
    unless ($self->{Inv}->add($item)) {       # And into their grubby hands
      $self->saymsg("[subj] don't have room for that many items!");
      next;
    }
    $heap->{Args}[$cnt++] = $item;  # The container may have modified it
    # TODO better way...
    $self->saymsg("[subj] picks up [the 1].", $item) unless $self->player;
  }
}

###########################################################################################

sub BEFORE_drop {
  my ($self, $heap, $item) = actargs @_;

  return STOP($self, "[subj] doesn't have [a 1]!", $item) unless $self->has($item);

  if ($item->{On}) {
    # It's equipped; so try to unequip it first.
    # TODO how do dependent actions work? hrm
    return STOP unless $self->unequip($item);
  }
}

sub ON_drop {
  my ($self, $heap, $item) = actargs @_;

  $item->{Owner}->del($item);                                  # Get out of their hands
  $self->{Map}->inv($self->{Y}, $self->{X}, "add", $item);     # And into onto the tile
  $self->saymsg("[subj] drops [the 1].", $item);
}

###########################################################################################

sub BEFORE_changedepth {
  my ($self, $heap) = actargs @_;

  my $stair = $self->tile->{Stair};
  if ($self->{Map}->normal and !$stair) {
    # We will always lack a way DOWN.
    GAME->addlvl($self->{Map}{Depth} + 1);
  } elsif (!$stair and my $rm = $self->tile->{HotelRm}) {
    GAME->addlvl("Room$rm" => BDSM::DunGen::GuestRoom->generate);
    # TODO dont hardcode spawnpoints
    $self->{Map}->stair($self->{Y}, $self->{X}, "Room$rm", 15, 20);
  } elsif (!$stair) {
    return STOP($self, "This staircase leads nowhere; sounds like someplace you'd like to
                        go?");
  }
  $stair = $self->tile->{Stair};

  my ($z, @to) = @$stair;
  my $map = GAME->{Levels}{$z} or return STOP($self, "Map $z not loaded because Breeg was testing things quickly, bug him to enable it");

  my ($y, $x);
  if (@to == 2) {
    ($y, $x) = @to;
  } else {
    ($y, $x) = $map->spawnpt(@to);
  }
  $heap->{To} = [$z, $y, $x];

  return STOP($self, "The staircase is blocked.") if ref $map->get($y, $x);
}

sub ON_changedepth {
  return unless GAME->fullsim;
  my ($self, $heap) = actargs @_;

  my ($z, $y, $x) = @{ $heap->{To} };
  my $map = GAME->{Levels}{$z};
  $heap->{OldMap} = $self->{Map};
  $self->{Map}->quit($self);
  $self->_blitoff;
  ($self->{Map}, $self->{Y}, $self->{X}) = ($map, $y, $x);
  $self->_bliton;
  $self->{Map}->join($self);
}

###########################################################################################

sub BEFORE_equip {
  my ($self, $heap, $item, $slot) = actargs @_;

  return STOP($self, "[subj] can't equip [a 1]!", $item) unless $item->is("Equipment");

  return STOP($self, "[subj] doesn't have [a 1]!", $item) unless $self->has($item);

  # Is the item already equipped?
  return STOP($self, "[subj] is already equipping [the 1]!", $item) if $item->{On};

  # Does the item fit there?
  return STOP($self, "[subj] can't equip [the 1] there!", $item) unless grep(/$slot/, $item->Fits);

  # Is that slot free? Try to unequip it if we do.
  if ($self->{Equipment}{$slot}) {
    return STOP unless $self->unequip($self->{Equipment}{$slot});
  }
}

sub ON_equip {
  my ($self, $heap, $item, $slot) = actargs @_;

  $self->{Equipment}{$slot} = $item;
  $item->{On} = $slot;
}

###########################################################################################

sub BEFORE_unequip {
  my ($self, $heap, $item) = actargs @_;

  # Do we have it?
  return STOP($self, "[subj] doesn't have [a 1]!", $item) unless $self->has($item);

  # Is it equipped?
  return STOP($self, "[subj] doesn't have [a 1] equipped!", $item) unless $item->{On};
}

sub ON_unequip {
  my ($self, $heap, $item) = actargs @_;

  delete $self->{Equipment}{ $item->{On} };
  $heap->{OldSlot} = delete $item->{On};  # Good to know for messaging
}

###########################################################################################

sub BEFORE_use {
  my ($self, $heap, $item) = actargs @_;

  return STOP($self, "[subj doesn't have [a 1]!", $item) unless $self->has($item);
  #return STOP($self, "[subj] can't $verb [a 1]!", $item) if $err;
}

sub ON_use {
  my ($self, $heap, $item) = actargs @_;

  $item->destroy if $item->is("SingleUse");
  my $verb = $item->Verb || "uses";
  $self->saymsg("[subj] $verb a " . $item->name . "."); # [a 1] fails because of Qty.. shit
  $item->fxn("WhenUsed", $self);
  42; # If fxn returns a special code, we could confuse do_act :P
}

###########################################################################################

sub ON_death {
  my ($self, $heap, $killer) = actargs @_;
  $self->{Dead} = 1;  # Relevant
  # Suicide does not merit reward!
  $killer->gainexp($self->{ExpWorth}) if GAME->fullsim and $killer->is("Player") and $self != $killer;

  $self->cleanup;
}

###########################################################################################

sub BEFORE_attack {
  my ($self, $heap, $name, @in) = actargs @_;

  if (@in == 2 and !ref $in[0]) {
    @in = ({ Y => $in[0], X => $in[1] });
  }
  if (@in > 1) {
    debug [$name, @in];
    die "too many args to attack!\n";
  }
  my $target = $in[0];

  # Right now we shouldn't ever have more than one $target walking in.

  my $attack = $self->Attacks($name)->clone($self);

  # Make sure the attack will work. This is repeated in PRE_attack, but doesn't matter.
  if (my $esm = $attack->{ESMCost}) {
    return STOP($self, "[the 0] doesn't have enough ESM to $attack->{Name}!") if $self->{ESM}->value < $esm;
    $self->{ESM}->mod($self->{ESM}->value - $esm);
  }
  if ($attack->{Check}) {
    my $code = $attack->{Check}->($self, $target);
    return STOP if $code and $code eq ":STOP";
  }

  $heap->{Args} = [$attack->{Name}, $target];
}

sub ON_attack {
  my ($self, $heap, $name, $target) = actargs @_;
  die "dont have $name" unless $self->Attacks($name);
  my $attack = $self->Attacks($name)->clone($self);

  # Now play with the range and get the targets.
  my ($range, @rargs) = @{ $attack->{Range} };
  $range = "range_$range";
  my @pwn = $attack->$range($heap, $self, $target, @rargs);
  return @pwn if @pwn and $pwn[0] eq ":STOP";
  $heap->{targets} = \@pwn;

  my @whom = @pwn;
  @whom = ($target) if !@whom and is_obj($target);
  $attack->cb_targets($heap, $self, @whom) if @whom;

  $attack->cb_pts($heap, $self) if $heap->{pts};

  # TODO secure this better, both sides.
  snooze $heap->{delay} if $heap->{delay};

  $attack->cb_rays($heap, $self) if $heap->{rays};

  return STOP($self, "[subj] doesn't hit anything with its $name attack!") unless @pwn;

  $attack->{Before}->($attack, $heap, $self) if $attack->{Before};
  $attack->damage($heap, $self) if GAME->fullsim;
  $attack->{After}->($attack, $heap, $self) if $attack->{After};

  delete $self->{Attacks}{$name} if $attack->{TmpAttack};
}

###########################################################################################

sub BEFORE_interact {
  my ($self, $heap) = actargs @_;
  my $r = $self->tile->{Region} or return STOP($self, "Nothing nearby appears useful.");
  $heap->{Args} = [$r];
}

sub ON_interact {
  my ($self, $heap, $r) = actargs @_;
  # TODO not sure how complex these'll get. plus, how to separate better? and by map?
  if ($r eq "fireplace") {
    $self->saymsg("[subj] gazes into the flames intensely.");
  }
  #UI->make_ripple(start => [$self->{Y}, $self->{X}]);
}

42;
