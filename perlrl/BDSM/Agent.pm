package BDSM::Agent;

use strict;
use warnings;
use Util;

use BDSM::Vector;

use base "Game::Object";
__PACKAGE__->announce("Agent");

__PACKAGE__->classdat(
  Symbol => "@",
  Color  => "white",
  Name   => "Agent Smith",
  name   => "Unnamed?"  # TODO bothh?
);

# Let there be moving life
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);
  return $self if $opts{no_init};
  $self->_construct(\%opts => "Map", "Symbol", "Color", "Name");
  
  $self->{TurnCntr} = 0;  # This is a fullsim thing, but it doesnt hurt anyone.
  $self->{Sprite} = $self->{Aggregate} = $self;   # We being bullied? Talk to us, then.

  # Determine name offset
  my $name = $self->name;
  $self->{NameOff} = center(1, length $name) if $name;

  # Going somewhere already?
  if ($self->{Map}) {
    $opts{At} ? $self->go(-nointeract => 1, @{ $opts{At} }) : $self->warp(delete $opts{spawn});
    $self->{Map}->join($self);
  }

  return $self;
}

# Can we move there?
sub _preblit {
  my ($self, $heap, $y, $x, $interact) = @_;

  return unless $self->{Map}->stfucheck($y, $x);  # Valid coordinates?

  my $tile = $self->{Map}->get($y, $x);
  # Something's there... collide with them, maybe.
  if (ref $tile) {
    return unless $interact;
    # If we're not in a Blob and collide with a Blob, push entire Blob
    # If we push something in a Blob and we're in it too, just push the thing
    # If our Aggregate isn't us, we're in a Blob.
    if ($self->{Aggregate} == $self) {
      return $self->fxn("WhenCollide", $heap, $tile->{Aggregate}, $y, $x);
    } else {
      return $self->fxn("WhenCollide", $heap, $tile->{Sprite}, $y, $x);
    }
  } else {
    return unless $self->{Map}->permeable($tile);
  }

  return 1;
}

# Erase ourselves from the map.
sub _blitoff {
  my $self = shift;
  return if $self->void;  # Can't do this yet
  delete $self->{Map}->tile($self->{Y}, $self->{X})->{Actor};
  $self->{Map}->modded($self->{Y}, $self->{X});

  $self->nameoff if $self->{ShowName};
}

# Draw ourselves onto the map.
sub _bliton {
  my $self = shift;

  debug "blit on issue? $self->{Y}, $self->{X}" unless $self->{Map}->tile($self->{Y}, $self->{X});
  $self->{Map}->tile($self->{Y}, $self->{X})->{Actor} = $self;
  $self->{Map}->modded($self->{Y}, $self->{X});

  # Draw name
  $self->nameon if $self->{ShowName};
}

sub nameoff {
  my $self = shift;
  return unless $self->{ShowName};
  my $cnt = 0;
  my $x = $self->{X} - $self->{NameOff};
  my $name = $self->name;
  foreach (split(//, $name)) {
    last if $self->{Y} - 2 < 0;
    $cnt++, next if $x + $cnt < 0 or $x + $cnt > $self->{Map}->width;
    # Erase our specific name
    $self->{Map}->del($self->{Y} - 2, $x + $cnt, "name", [ 3 => $self->{ID} ]);
    $cnt++;
  }
}

sub nameon {
  my $self = shift;
  my $cnt = 0;
  my $x = $self->{X} - $self->{NameOff};
  my $name = $self->name;
  my $color = $self->Color;
  $color = "black/$color" unless $color =~ m#/#;  # Don't get complicated
  foreach (split(//, $name)) {
    last if $self->{Y} - 2 < 0;
    $cnt++, next if $x + $cnt < 0 or $x + $cnt > $self->{Map}->width;
    $self->{Map}->mod($self->{Y} - 2, $x + $cnt, name => $_, $color, $self->{ID});
    $cnt++;
  }
}

# If we're omnomnomed by a blob, we need to report our unicellularnicity.
sub height { 0 }
sub width  { 0 }

# Return what we're standing on.
sub tile {
  my $self = shift;
  return $self->{Map}->tile($self->{Y}, $self->{X});
}

# Do we submit to somebody pushing us?
sub pushedby {
  my ($self, $pusher) = @_;
  return "attack" if $self->is("Monster");   # Hostile!
  #return "swap";
  return "push";
}

# Draw us
sub display {
  my $self = shift;
  return ($self->Symbol, $self->Color);
}

# Don't abuse this. A way of knowing if we're anywhere yet or not
sub void {
  my $self = shift;
  return !defined($self->{Y});
}

# Are we?
sub adj {
  my ($self, $other) = @_;
  return 0 if abs($self->{Y} - $other->{Y}) > 1 or abs($self->{X} - $other->{X}) > 1;
  return 1;
}

###########################################################################################

sub BEFORE_go {
  my ($self, $heap, $y, $x) = actargs @_;
  $y = int $y; $x = int $x;
  @{ $heap->{Args} } = ($y, $x);
  debug("out of bounds. $y, $x on $self->{Map}{Depth}"), return STOP unless $self->{Map}->stfucheck($y, $x);
  debug("same coords!"), return STOP if !$self->void and $y == $self->{Y} and $x == $self->{X};
  return 1 if $heap->{swap};  # We're deliberately doing something weird here

  # 1) We have to get off our tile... if we can.
  # TODO figure out who needs to run onetner and onexit if we're server/client
  if (!$self->void and $self->tile->{OnExit}) {
    my @code = $self->tile->{OnExit}->("BEFORE", $self, $heap);
    return @code unless @code == 1;   # Handle the return code; this is an abnormal event.
  }

  # 2) Now check out where we're trying to go...
  my $do = $self->_preblit($heap, $y, $x, !$heap->{nointeract});
  return REDIRECT("attack", $self->{CloseAttack}, $do) if ref $do;
  return STOP unless $do;
}

sub ON_go {
  my ($self, $heap, $y, $x) = actargs @_;

  # This time, let the client do something
  # TODO both need to maybe do this?
  if (!$self->void and $self->tile->{OnExit}) {
    $self->tile->{OnExit}->("ON", $self, $heap);
    # Return code means nothing on client-side; we've already decided to go cause server
  }

  # Blit off old position.
  if ($heap->{swap}) {
    $self->nameoff if $self->{ShowName};
  } else {
    $self->_blitoff;
  }

  # Track our last move; AIs and other local map searching state machines could use this
  $self->{LastMv} = $heap->{From} = [$self->{Y}, $self->{X}] unless $self->void;
  ($self->{Y}, $self->{X}) = ($y, $x);

  # Blit onto new position.
  $self->_bliton;

  # Let the new tile react to us.
  # TODO give heap to those, they can return things that way!
  $self->tile->{OnEnter}->("ON", $self, $heap) if $self->tile->{OnEnter};

  # Cast a scent if we're the server.
  # TODO not really server, just.. ruling gamestate.
  $self->{TurnCntr}++;
  $self->{Map}->logicfov($self) if GAME->fullsim and $self->human_control;

  $self->saymsg("[subj] and [the 1] swap places.", GAME->{Objects}[ $heap->{swap}[0] ]) if ref $heap->{swap};

  $self->lag($self->{Map}{_Data}{mvlag} // 0);
}

###########################################################################################

sub BEFORE_warp {
  my ($self, $heap, $group) = actargs @_;
  if ($group and $group eq "anywhere") {
    return REDIRECT("go", -nointeract => 1, $self->{Map}->getpt(-match => " "));
  } else {
    return REDIRECT("go", -nointeract => 1, $self->{Map}->spawnpt($group));
  }
}

###########################################################################################

sub WhenCollide {
  my ($self, $heap, $victim, $toy, $tox) = @_;
  $heap->{Collided} = $victim;

  # talk to em, attack em, interact... but by default, just push!
  my $interact = $victim->pushedby($self);
  if ($interact eq "push") {
    # Hey, they said we could.
    return STOP unless $victim->go(
      dir_relative(
        dir_of(from => [$self->{Y}, $self->{X}], to => [$toy, $tox]),
        $victim->{Y}, $victim->{X}
      )
    );
    return 1;
  } elsif ($interact eq "attack") {
    return $victim;
  } elsif ($interact eq "swap") {
    $victim->go(-swap => 1, $self->{Y}, $self->{X});
    $self->go(-swap => [$victim->{ID}], $toy, $tox);
    return STOP;
  } else {
    return STOP;   # They refused to even try to move
  }
}

###########################################################################################

sub BEFORE_n  { REDIRECT("go", north_of( shift() )) }
sub BEFORE_s  { REDIRECT("go", south_of( shift() )) }
sub BEFORE_w  { REDIRECT("go", west_of( shift() )) }
sub BEFORE_e  { REDIRECT("go", east_of( shift() )) }
sub BEFORE_nw { REDIRECT("go", northwest_of( shift() )) }
sub BEFORE_ne { REDIRECT("go", northeast_of( shift() )) }
sub BEFORE_sw { REDIRECT("go", southwest_of( shift() )) }
sub BEFORE_se { REDIRECT("go", southeast_of( shift() )) }

# TODO alright, annoyed by this, but i'm intending PRE to be a non-gamestate critical bit..
sub PRE_n  { REDIRECT("go", north_of( shift() )) }
sub PRE_s  { REDIRECT("go", south_of( shift() )) }
sub PRE_w  { REDIRECT("go", west_of( shift() )) }
sub PRE_e  { REDIRECT("go", east_of( shift() )) }
sub PRE_nw { REDIRECT("go", northwest_of( shift() )) }
sub PRE_ne { REDIRECT("go", northeast_of( shift() )) }
sub PRE_sw { REDIRECT("go", southwest_of( shift() )) }
sub PRE_se { REDIRECT("go", southeast_of( shift() )) }

42;
