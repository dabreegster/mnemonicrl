##############################
# StdLib::Character::Monster #
##############################

package Roguelike::StdLib::Character::Monster;

use strict;
use warnings;
use Roguelike::Game;
use Roguelike::Utility;

use Roguelike::Container;

# Definition

my $monster = $Game->{Templates}{Character}->new(
  Symbol => "@",  # Ah, the nostalgia...
  Init => sub {
    my $self = shift;
    # Whoa, wait, are we an instance? If we are, we have Z, Y, and X. No base.
    if (defined $self->{Z} and defined $self->{Y} and defined $self->{X}) {
      # Set up some stuff up...
      $self->{Inv} = new Roguelike::Container 0, $self;
      if ($self->go( $self->g("Z"), $self->g("Y"), $self->g("X") ) == -1) {
        debug "$self->{Z}, $self->{Y}, $self->{X}... why can't we go?";
        debug $Game->{Levels}[$self->{Z}]{Map}[$self->{Y}][$self->{X}];
        return -1;
      }
      # Register ourselves in the area's list.
      unless ($self->g("Area")) {
        debug "$self->{Z}, $self->{Y}, $self->{X}... why can't we go?";
        debug $Game->{Levels}[$self->{Z}]{Map}[$self->{Y}][$self->{X}];
        return -1;
      } else {
        push @{ $self->g("Area")->{Monsters} }, $self;
        # And queue ourselves
        $self->schedule(1, sub { $self->Input() });
      }
    }
  },
);

# Reactions

# None yet. :(

# Actions

sub PRE_die { (0, "die", "-") }

sub die {
  my $self = shift;
  my $selfdestruct = shift;
  # Erase ourselves from the map.
  $self->tile->{Char} = undef;
  render($self->tile);
  # Remove self from list.
  # Just loop through for now. Whatever.
  foreach (0 .. $#{ $self->g("Area.Monsters") }) {
    splice(@{ $self->g("Area.Monsters") }, $_, 1) if $self->g("ID") ==
    $self->g("Area.Monsters.$_.ID");
  }
  # Now do the same for the queue.
  foreach (0 .. $#{ $Game->{Queue} }) {
    my $tmp = [];
    foreach (0 .. $#{ $Game->{Queue} }) {
      push @$tmp, $Game->{Queue}[$_] unless $Game->{Queue}[$_]{Actor}->g("ID") == $self->g("ID");
    }
    @{ $Game->{Queue} } = @{ $tmp };
  }
  # For now, only the player kills monsters... This is so messy!
  if ($selfdestruct) {
    $self->msg("<Red>[subj] is obliterated.");
  } else {
    $Player->msg("<Red>[subj] kill the [1]!", $self);
    # Experience.
    $Player->gainexp( $self->g("Exp") );
  }
  undef $self;  # Weak references better be good for something. Assume there
                # are no others.
}

sub UTIL_Input {
  my $self = shift;
  my ($energy, $action, @args);
  # We active?
  if ($Game->{Active}{ $self->{ID} }) {
    my @results = $self->g("Behavior", $self);
    if (@results == 1) {
      $energy = -1;
    } else {
      ($energy, $action, @args) = @results;
    }
    # -1 energy from @results means... we screwed up. Oh well.
    if ($energy == -1) {
      ($energy, $action, @args) = $self->_idle;
    }
    if ($energy == 1) {
      $self->queue($action, @args)->();
      return 1;
    }
  } else {
    ($energy, $action, @args) = $self->_idle;
  }
  $self->schedule($energy, $self->queue("_${action}_", @args) );
  return 1;
}

define(Monster => $monster, [
  "die"
]);

42;
