package Game::Container;

use strict;
use warnings;
use Util;

# Create a new container to keep track of an inventory.
sub new {
  my ($class, $owner) = @_;
  my $self = bless {
    Index    => {},
    Category => {},
    Owner    => $owner
  }, $class;
  return $self;
}

# Grab an item from the container.
sub get {
  my ($self, $idx) = @_;
  return $self->{Index}{$idx};
}

# Return all our stuff or a subset of it.
sub all {
  my $self = shift;
  if (my $cat = shift) {
    return () unless values %{ $self->{Category}{$cat} };
    return sort { $a->{Index} cmp $b->{Index} } values %{ $self->{Category}{$cat} };
  } else {
    return () unless values %{ $self->{Index} };
    return sort { $a->{Index} cmp $b->{Index} } values %{ $self->{Index} };
  }
}

# Add an object to the container.
sub add {
  my ($self, $obj) = @_;
  
  # Should we combine this item with an existing one?
  my @groupby = $obj->GroupBy;
  TWIN: foreach my $twin ($self->all( $obj->Category )) {
    last unless @groupby;   # None indicates we never wanna group this stuff
    foreach my $attrib (@groupby) {
      next TWIN if $obj->$attrib ne $twin->$attrib;
    }
    # *sniffle* long lost twins, separated at birth, reunited...!
    $twin->{Qty} += $obj->{Qty};
    # Reference magic to make the item passed in equal the new composite itme.
    $_[1] = $twin;
    return $twin;
  }

  # Nah, new item.
  # Find the next free letter for it.
  my $letter;
  foreach ("a" .. "z", "A" .. "Z") {
    $letter = $_, last unless $self->{Index}{$_};
  }
  return unless $letter;  # Full
  $obj->{Owner} = $self;
  $obj->{Index} = $letter;
  $self->{Index}{$letter} = $obj;
  $self->{Category}{ $obj->Category }{$letter} = $obj;
  return $obj;
}

# Add an item to the container, but mimic the server's representation
sub _client_add {
  my ($self, $obj) = @_;
  $obj->{Owner} = $self;
  my $letter = $obj->{Index};   # it already knows
  $self->{Index}{ $letter } = $obj;
  $self->{Category}{ $obj->Category }{$letter} = $obj;
  return $obj;
}

# Take an object out from the container.
sub del {
  my ($self, $obj) = @_;
  die "obj's owner isnt this container" if $self != $obj->{Owner};
  my $letter = $obj->{Index};
  my $cat = $obj->Category;
  delete $obj->{Owner};
  delete $self->{Index}{$letter};
  delete $self->{Category}{$cat}{$letter};
  # Nuke the category entirely if it's empty
  delete $self->{Category}{$cat} unless %{ $self->{Category}{$cat} };
}

42;
