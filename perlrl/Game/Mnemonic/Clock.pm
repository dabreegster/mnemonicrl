package Game::Mnemonic::Clock;

use strict;
use warnings;
use Util;

use base "Game::Object";
__PACKAGE__->announce("HotelClock");

sub new {
  my ($class, %opts) = @_;
  my $self = $class->SUPER::new(%opts, Global => 1);
  $self->_construct(\%opts => "Hour", "Min");
  $self->{Hour} //= 0;
  $self->{Min} //= 0;

  $self->schedule(
    -do   => "time_next",
    -id   => "hotel_clock",
    -tags => ["gamestate"]
  );

  return $self;
}

sub BEFORE_time_next {
  my ($self, $heap) = actargs @_;
  my ($min, $hr) = ($self->{Min}, $self->{Hour});
  if (++$min == 60) {
    $min = 0;
    if (++$hr == 24) {
      $hr = 0;
    }
  }
  return REDIRECT("time_set", $hr, $min);
}

sub ON_time_set {
  my ($self, $heap, $hr, $min) = actargs @_;
  ($self->{Min}, $self->{Hour}) = ($min, $hr);
  $heap->{Return} = CFG->{Hotel}{ClockMin};
}

sub mins_left {
  my $self = shift;
  return (23 - $self->{Hour}) * 60 + (59 - $self->{Min});
}

42;
