package PerlRL::Component::View::Actions;

use strict;
use warnings;
use Util;

# No point in convoluted symbol table wizardry... just plop right on in and spew our load.

package BDSM::Agent;

sub AFTER_go {
  my ($self, $heap, $y, $x) = actargs @_;
  if ($self->{tracked}) {
    UI->{Main}->target_undraw(@{ $heap->{From} });
    UI->{Main}->target_draw($y, $x);
  }
  # Alright so this isnt necessarily our job, but it needs to go in this order or else
  # player's camera is funkitated. technically we should workaround, because this could
  # have legitimate other callback uses TODO
  $self->{Map}->hookshot("draw" => $self);
}

# Handle focus events
sub on_screen {
  my $self = shift;
  
  # Don't always display the banner
  return unless $self->{Map}{_Data}{nametags} and $self->Unique;
  return if $self->{ShowName};  # Already on
  $self->{ShowName} = 1;
  $self->nameon;
}

sub off_screen {
  my $self = shift;
  $self->nameoff;
  $self->{ShowName} = 0;
}

package Game::StdLib::Character::Player;

sub AFTER_go {
  my ($self, $heap, $y, $x) = actargs @_;
  return unless $self->player;

  # TODO again with the pre/before distinction..
  $self->lstile(-stages => ["Pre"]);

  UI->{Status}->update("Coords") if UI->{Status};

  # Handle layers
  my $layer;
  if ($layer = $self->tile->{Layer} and !$self->{Map}{LayerOff}) {
    # Erase the layer
    $self->{Map}{LayerOff} = $layer;
    foreach (@{ $self->{Map}{Layer}{$layer} }) {
      $self->{Map}->tile(@$_)->{LayerOff} = 1;
      $self->{Map}->modded(@$_);
    }
  } elsif (!$layer and $layer = delete $self->{Map}{LayerOff}) {
    # Make it reappear
    foreach (@{ $self->{Map}{Layer}{$layer} }) {
      delete $self->{Map}->tile(@$_)->{LayerOff};
      $self->{Map}->modded(@$_);
    }
  }
  # TODO: no adjacent layers or overlaps ><

  UI->{Main}->light($self);
  UI->{Main}->focus($self);

  my $r;
  if ($r = $self->tile->{Region} and my $descr = $self->{Map}{_Data}{Descr}{$r}) {
    my $old = $self->{Map}->tile(@{ $heap->{From} })->{Region};
    msg see => $descr if !$old or $old ne $r;
  }

  $self->super(-start => "Character", "AFTER_go", $heap);
}

sub ON_journal {
  my ($self, $heap, @ls) = actargs @_;
  my @entries = sort { $a->Name cmp $b->Name } map { GAME->{Templates}{$_} } @ls;
  my @lines = map { $_->Name } @entries;
  while (1) {
    my $idx = UI->choose(-idx => 1, "Journal", "<cyan>Back to exploring", @lines);
    return STOP;
    # TODO yeah describe doesnt work great on a package.
    #return STOP unless $idx;
    #UI->popup($entries[$idx - 1]->describe);
  }
} 

sub AFTER_gainexp {
  my ($self, $heap, $xp) = actargs @_;
  UI->{Status}->update("Rank");
  UI->{Status}->update("Exp");
}

package Game::StdLib::Character::Monster;

# Print a description
sub on_screen {
  my $self = shift;
  
  if (Player->{Explore} and $self->tile->{Lit} == 2) {
    GAME->unschedule(-tags => ["explore"]);
    delete Player->{Explore};
    msg err => "There's a monster nearby, so you can't explore safely.";
  }
  
  return if Player->{Seen}{ $self->type }++;
  msg see => $self->Descr;
}

package BDSM::Agent::Blob;

sub AFTER_go {
  my $self = shift;
  # It's best this happens right before we redraw
  UI->{Main}->focus if $self->{Camera};
  # And draw changes.
  $self->{Map}->hookshot("draw" => $self);
}

package Game::StdLib::Character;

sub WhenCleanup {
  my $self = shift;
  delete UI->{Main}{OnScreen}{ $self->{ID} };
  UI->{Main}->drawme;
  debug "cleaning up $self->{ID} and current battling is " . UI->{Battling}{ID};
  if (UI->{Battling}{ID} == $self->{ID}) {
    UI->{Battling} = { ID => -1 };
    UI->{Bar}->update("ThemHP");
  }
}

sub AFTER_equip {
  my ($self, $heap, $item, $slot) = actargs @_;
  my $verb = $slot eq "Weapon" ? "wields" : "puts on";
  $self->saymsg("[subj] $verb [the 1].", $item);
  $self->saymsg("Haha, nice equipment");
  UI->{Status}->update($slot) if $self->player and UI->{Status}{Entries}{$slot};
}

sub AFTER_unequip {
  my ($self, $heap, $item) = actargs @_;
  my $verb = $heap->{OldSlot} eq "Weapon" ? "unwields" : "takes off";
  $self->saymsg("[subj] $verb [the 1].", $item);
  my $slot = $heap->{OldSlot};
  UI->{Status}->update($slot) if $self->player and UI->{Status}{Entries}{$slot};
}

sub AFTER_death {
  my ($self, $heap, $killer) = actargs @_;
  $killer->saymsg("[subj] kills [the 1]!", $self);
}

package Game::Mnemonic::Clock;

sub AFTER_time_set {
  my ($self, $heap, $hr, $min) = actargs @_;
  UI->{Bar}->update(Clock => sprintf("%02d", $hr), sprintf("%02d", $min));
}

42;
