# Copyright 2007, 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.

package Gtk2::Ex::CrossHair;
use strict;
use warnings;
use Carp;
use List::Util;
use POSIX ();

# 1.200 for EVENT_PROPAGATE, Gtk2::GC auto-release
use Gtk2 '1.200';
use Gtk2::Ex::Xor;

our $VERSION = 4;

# set this to 1 for some diagnostic prints
use constant DEBUG => 0;


use constant DEFAULT_LINE_STYLE => 'on_off_dash';

use Glib::Object::Subclass
  Glib::Object::,
  signals => { moved => { param_types => ['Gtk2::Widget',
                                          'Glib::Scalar',
                                          'Glib::Scalar'],
                          return_type => undef },
             },
  properties => [ Glib::ParamSpec->scalar
                  ('widgets',
                   'widgets',
                   'Arrayref of widgets to act on.',
                   Glib::G_PARAM_READWRITE),

                  Glib::ParamSpec->object
                  ('widget',
                   'widget',
                   'Single widget to act on.',
                   'Gtk2::Widget',
                   Glib::G_PARAM_READWRITE),

                  Glib::ParamSpec->boolean
                  ('active',
                   'active',
                   'Whether to display the crosshair.',
                   0,
                   Glib::G_PARAM_READWRITE),

                  Glib::ParamSpec->scalar
                  ('foreground',
                   'foreground',
                   'The colour to draw the crosshair, either a string name (including hex RGB), a Gtk2::Gdk::Color, or undef for the widget\'s style foreground.',
                   Glib::G_PARAM_READWRITE),

                  # not a documented feature yet ... and the line crossover
                  # isn't drawn particularly well for wide lines yet ... and
                  # without the zero-width hardware accelerated line it
                  # might need SyncCall ...
                  Glib::ParamSpec->int
                  ('line-width',
                   'line-width',
                   'The width of the cross lines drawn.',
                   0, POSIX::INT_MAX(),
                   0, # default
                   Glib::G_PARAM_READWRITE),
                ];


sub INIT_INSTANCE {
  my ($self) = @_;
  $self->{'button'} = 0;
  $self->{'widgets'} = [];
}

sub FINALIZE_INSTANCE {
  my ($self) = @_;
  if (DEBUG) { print "CrossHair finalize\n"; }
  _cleanup_widgets ();
  $self->end;
}

sub _cleanup_widgets {
  my ($self) = @_;
  foreach my $widget (@{$self->{'widgets'}}) {
    delete $widget->{__PACKAGE__,$self,'gc'};
  }
}
sub _do_style_set {
  my ($widget, $prev_style, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return;
  delete $widget->{__PACKAGE__,$self,'gc'};
}

sub GET_PROPERTY {
  my ($self, $pspec) = @_;
  my $pname = $pspec->get_name;
  if ($pname eq 'widget') {
    my $widgets = $self->{'widgets'};
    if (@$widgets > 1) {
      croak __PACKAGE__.": cannot get single 'widget' property when using multiple widgets";
    }
    return $widgets->[0];
  }
  return $self->{$pname};
}

sub SET_PROPERTY {
  my ($self, $pspec, $newval) = @_;
  my $pname = $pspec->get_name;
  my $oldval = $self->{$pname};
  if (DEBUG) { print "cross set '$pname' ",
                 defined $newval ? $newval : 'undef',"\n"; }

  if ($pname eq 'widget') {
    $pname = 'widgets';
    $newval = [ $newval ];
    $self->notify ('widgets');
  }

  if ($pname eq 'widgets') {
    my $widgets = $newval;

    _cleanup_widgets (); # old settings

    # These are events we'll need on in button drag mode, when start() is
    # called with a button event.  The alternative would be to turn them on
    # by a new Gtk2::Gdk->pointer_grab() to change the implicit grab, though
    # 'button-release-mask' is best turned on in advance in case we're
    # lagged and it happens before we change the event mask.
    #
    # 'exposure-mask' is not here since if nothing else is drawing then
    # there's no need for us to redraw over its changes.
    #
    my @static_setups;
    $self->{'static_setups'} = \@static_setups;
    my $ref_weak_self = Gtk2::Ex::Xor::_ref_weak ($self);
    require Glib::Ex::SignalIds;

    foreach my $widget (@$widgets) {
      push @static_setups, Glib::Ex::SignalIds->new
        ($widget,
         $widget->signal_connect (style_set => \&_do_style_set,
                                  $ref_weak_self));

      #       require Gtk2::Ex::WidgetEvents;
      #       push @static_setups, Gtk2::Ex::WidgetEvents->new
      #         ($widget, ['button-motion-mask',
      #                    'button-release-mask' ]);

      $widget->add_events(['button-motion-mask',
                           'button-release-mask',
                           'pointer-motion-mask',
                           'enter-notify-mask',
                           'leave-notify-mask']);
    }

  } elsif ($pname eq 'active') {
    # the extra '$self->notify' calls by running 'start' and 'end' here are
    # ok, Glib suppresses duplicates while in a SET_PROPERTY
    if ($newval && ! $oldval) {
      $self->start;
    } elsif ($oldval && ! $newval) {
      $self->end;
    }

  } elsif ($pname eq 'foreground' || $pname eq 'line_width') {
    if ($self->{'drawn'}) { _draw ($self); } # undraw
    _cleanup_widgets ($self);  # new colour
    $self->{$pname} = $newval;
    if ($self->{'active'}) { _draw ($self); }
  }

  $self->{$pname} = $newval;  # per default GET_PROPERTY
}

sub start {
  my ($self, $event) = @_;

  if (ref $event && $event->can ('button')) {
    $self->{'button'} = $event->button;
  } else {
    $self->{'button'} = 0;
  }
  if ($self->{'active'}) { return; }

  _start ($self, $event);
  $self->notify('active');
}

sub _start {
  my ($self, $event) = @_;
  if (DEBUG) { print "CrossHair start\n"; }
  $self->{'active'} = 1;
  $self->{'drawn'} = 0;

  my $widget_list = $self->{'widgets'};
  my ($widget, $x, $y);

  my @dynamic_setups;
  $self->{'dynamic_setups'} = \@dynamic_setups;
  my $ref_weak_self = Gtk2::Ex::Xor::_ref_weak ($self);

  require Glib::Ex::SignalIds;
  foreach my $widget (@$widget_list) {
    push @dynamic_setups, Glib::Ex::SignalIds->new
      ($widget,
       $widget->signal_connect (motion_notify_event => \&_do_motion_notify,
                                $ref_weak_self),
       $widget->signal_connect (button_release_event => \&_do_button_release,
                                $ref_weak_self),
       $widget->signal_connect (enter_notify_event => \&_do_enter_notify,
                                $ref_weak_self),
       $widget->signal_connect (leave_notify_event => \&_do_leave_notify,
                                $ref_weak_self),
       $widget->signal_connect_after (expose_event => \&_do_expose_event,
                                      $ref_weak_self),
       $widget->signal_connect_after (size_allocate => \&_do_size_allocate,
                                      $ref_weak_self));

    # These are basically events needed when enabled through the keyboard or
    # whatever non-button-press.
    #
    #     push @dynamic_setups, Gtk2::Ex::WidgetEvents->new
    #       ($widget, ['pointer-motion-mask',
    #                  'enter-notify-mask',
    #                  'leave-notify-mask' ]);
  }

  require Gtk2::Ex::WidgetCursor;
  push @dynamic_setups, Gtk2::Ex::WidgetCursor->new
    (widgets => $widget_list,
     cursor  => 'invisible',
     active  => 0);

  if (ref $event
      && $event->can ('button')
      && do {
        my $eventwidget = Gtk2->get_event_widget ($event);
        $widget = List::Util::first {$_ == $eventwidget} @$widget_list;
      }) {
    # button press in one of our widgets
    ($x, $y) = Gtk2::Ex::Xor::_event_widget_coords ($widget, $event);

  } elsif (my $first_widget = $widget_list->[0]) {
    # keyboard or programmatic, look for widget containing pointer
    my ($first_x, $first_y) = $first_widget->get_pointer;

    foreach my $try_widget (@$widget_list) {
      my ($try_x, $try_y) = $first_widget->translate_coordinates
        ($try_widget, $first_x, $first_y);
      if (_widget_contains_xy ($try_widget, $try_x, $try_y)) {
        $x = $try_x;
        $y = $try_y;
        $widget = $try_widget;
        last;
      }
    }
  }

  $self->{'xy_widget'} = $widget;
  $self->{'x'} = $x;
  $self->{'y'} = $y;
  if ($widget) { _draw ($self); }

  $self->signal_emit ('moved', $widget, $x, $y);
}

sub end {
  my ($self) = @_;
  if (! $self->{'active'}) { return; }

  if ($self->{'drawn'})  {
    _draw ($self);  # undraw
    $self->{'drawn'} = 0;
  }
  delete $self->{'dynamic_setups'};

  $self->signal_emit ('moved', undef, undef, undef);
  $self->{'active'} = 0;
  $self->notify('active');
}

# 'motion-notify-event' on a target widget
sub _do_motion_notify {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return Gtk2::EVENT_PROPAGATE;
  if (DEBUG) { print "crosshair motion ", $event->x, ",", $event->y, "\n"; }
  if (! $self->{'active'}) { return Gtk2::EVENT_PROPAGATE; }

  _maybe_move ($self, $widget,
               Gtk2::Ex::Xor::_event_widget_coords ($widget, $event));
  return Gtk2::EVENT_PROPAGATE;
}

# 'size-allocate' signal on the widgets
sub _do_size_allocate {
  my ($widget, $alloc, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return;
  if (! defined $self->{'xy_widget'}
      || $widget != $self->{'xy_widget'}) {
    return;
  }

  # if the xy_widget moves we've lost where it was before and so where the
  # lines in the other widgets were drawn, so just redraw the lot (perhaps
  # could keep track of the drawing on each in widget coordinates on each,
  # except probably that depends on NorthWest gravity)
  #
  foreach my $widget (@{$self->{'widgets'}}) {
    $widget->queue_draw;
  }
  # new widget coordinates
  _maybe_move ($self, $widget, $widget->get_pointer);
}

# 'enter-notify-event' signal on the widgets
sub _do_enter_notify {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return Gtk2::EVENT_PROPAGATE;
  if (DEBUG) { print "crosshair enter ", $event->x, ",", $event->y, "\n"; }
  if ($self->{'button'}) { return Gtk2::EVENT_PROPAGATE; } # not grab mode

  _maybe_move ($self, $widget,
               Gtk2::Ex::Xor::_event_widget_coords ($widget, $event));
  return Gtk2::EVENT_PROPAGATE;
}

# 'leave-notify-event' signal on the widgets
sub _do_leave_notify {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return Gtk2::EVENT_PROPAGATE;
  if (DEBUG) { print "crosshair leave ", $event->x, ",", $event->y, "\n"; }
  if ($self->{'button'}) { return Gtk2::EVENT_PROPAGATE; } # not grab mode

  _maybe_move ($self, undef, undef, undef);
  return Gtk2::EVENT_PROPAGATE;
}

# 'button-release-event' signal on the widgets
sub _do_button_release {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return Gtk2::EVENT_PROPAGATE;
  if ($event->button == $self->{'button'}) {
    $self->end ($event);
  }
  return Gtk2::EVENT_PROPAGATE;
}

sub _maybe_move {
  my ($self, $widget, $x, $y) = @_;

  $self->{'pending_widget'} = $widget;
  $self->{'pending_x'} = $x;
  $self->{'pending_y'} = $y;

  $self->{'sync_call'} ||= do {
    require Gtk2::Ex::SyncCall;
    Gtk2::Ex::SyncCall->sync ($self->{'widgets'}->[0],
                              \&_sync_call_handler,
                              Gtk2::Ex::Xor::_ref_weak ($self));
  };
}
sub _sync_call_handler {
  my ($ref_weak_self) = @_;
  my $self = $$ref_weak_self || return;
  $self->{'sync_call'} = undef;
  if (! $self->{'active'}) { return; }

  if ($self->{'drawn'}) {
    if (DEBUG >= 2) { print "  undraw\n"; }
    _draw ($self);
  }
  $self->{'xy_widget'} = $self->{'pending_widget'};
  $self->{'x'} = $self->{'pending_x'};
  $self->{'y'} = $self->{'pending_y'};
  _draw ($self);    # draw new

  $self->signal_emit ('moved',
                      $self->{'xy_widget'}, $self->{'x'}, $self->{'y'});
}

sub _do_expose_event {
  my ($widget, $event, $ref_weak_self) = @_;
  my $self = $$ref_weak_self || return Gtk2::EVENT_PROPAGATE;
  if (! $self->{'active'}) { return Gtk2::EVENT_PROPAGATE; }

  if (DEBUG) { print "CrossHair expose $widget\n"; }
  if ($self->{'drawn'}) {
    _draw ($self, [$widget], $event->region);  # redraw
  }
  return Gtk2::EVENT_PROPAGATE;
}

sub _draw {
  my ($self, $widgets, $clip_region) = @_;
  my $sx = $self->{'x'};
  my $sy = $self->{'y'};
  my $xy_widget = $self->{'xy_widget'} || return; # nothing to draw

  $widgets ||= $self->{'widgets'};
  foreach my $widget (@$widgets) {
    if (DEBUG) { print "  draw $widget\n"; }

    my $win = $widget->Gtk2_Ex_Xor_window || next; # perhaps unrealized
    my $gc = ($widget->{__PACKAGE__,$self,'gc'} ||= do {
      if (DEBUG) { print "  create gc\n"; }
      Gtk2::Ex::Xor::get_gc ($widget, $self->{'foreground'},
                             line_width => ($self->{'line_width'} || 0),
                             line_style => ($self->{'line_style'}
                                            || DEFAULT_LINE_STYLE),
                             cap_style => 'butt',
                             # subwindow_mode => 'include_inferiors',
                            );
    });

    my ($x, $y) = $xy_widget->translate_coordinates ($widget, $sx, $sy);
    if ($win != $widget->window) {
      my ($wx, $wy) = $win->get_position;
      if (DEBUG) { print "  subwindow offset $wx,$wy\n"; }
      $x -= $wx;
      $y -= $wy;
    }
    my ($x_lo, $y_lo, $x_hi, $y_hi);
    if ($widget->get_flags & 'no-window') {
      my $alloc = $widget->allocation;
      $x_lo = $alloc->x;
      $x_hi = $alloc->x + $alloc->width - 1;
      $y_lo = $alloc->y;
      $y_hi = $alloc->y + $alloc->height - 1;
      $x += $x_lo;
      $y += $y_lo;
    } else {
      ($x_hi, $y_hi) = $win->get_size;
      $x_lo = 0;
      $y_lo = 0;
    }
    if (DEBUG) { print "  at $x,$y\n"; }

    my $width = $self->{'line_width'} || 1;
    my $y_top = $y - POSIX::ceil ($width/2);
    my $y_bottom = $y_top + $width + 1;

    if ($clip_region) { $gc->set_clip_region ($clip_region); }
    $win->draw_segments
      ($gc,
       $x_lo, $y, $x_hi, $y, # horizontal
       ($y_lo <= $y_top ? ($x, $y_lo, $x, $y_top) : ()),
       ($y_bottom <= $y_hi ? ($x, $y_bottom, $x, $y_hi) : ()));
    if ($clip_region) { $gc->set_clip_region (undef); }
  }
  $self->{'drawn'} = 1;
}


#------------------------------------------------------------------------------
# generic helpers

# Return true if $x,$y in widget coordinates is within $widget's width and
# height.
sub _widget_contains_xy {
  my ($widget, $x, $y) = @_;
  return ($x >= 0 && $y >= 0
          && $x < $widget->allocation->width
          && $y < $widget->allocation->height);
}

#------------------------------------------------------------------------------


# Not sure about these yet:
#
#                   Glib::ParamSpec->enum
#                   ('line-style',
#                    'line-style',
#                    'blurb',
#                    'Gtk2::Gdk::LineStyle',
#                    DEFAULT_LINE_STYLE,
#                    Glib::G_PARAM_READWRITE),
#
#
# =item C<line_width> (default 0 thin line)
#
# =item C<line_style> (default C<on-off-dash>)
#
# Attributes for the graphics context (C<Gtk2::Gdk::GC>) used to draw.  New
# settings here only take effect on the next C<start>.  For example,
#
#     $crosshair->{'line_width'} = 3;
#     $crosshair->{'line_style'} = 'solid';



1;
__END__

=head1 NAME

Gtk2::Ex::CrossHair -- crosshair lines drawn following the mouse

=head1 SYNOPSIS

 use Gtk2::Ex::CrossHair;
 my $crosshair = Gtk2::Ex::CrossHair->new (widgets => [$w1,$w2]);
 $crosshair->signal_connect (moved => sub { ... });

 $crosshair->start ($event);
 $crosshair->end ();

=head1 OBJECT HIERARCHY

C<Gtk2::Ex::CrossHair> is a subclass of C<Glib::Object>.

    Glib::Object
      Gtk2::Ex::CrossHair

=head1 DESCRIPTION

A CrossHair object draws a horizontal and vertical line through the mouse
pointer position on top of one or more widgets' existing contents.  This is
intended as a visual guide for the user.

        +-----------------+
        |         |       |
        |         | mouse |
        |         |/      |
        | --------+------ |
        |         |       |
        |         |       |
        |         |       |
        |         |       |
        +-----------------+
        +-----------------+
        |         |       |
        |         |       |
        |         |       |
        +-----------------+

The idea is to help see relative positions.  For example in a graph the
horizontal line helps you see which of two peaks is the higher, and the
vertical line can extend down to (or into) an X axis scale to help see where
exactly a particular part of the graph lies.

The C<moved> callback lets you update a text status line with a position in
figures, etc (if you don't display something like that following the mouse
all the time).

While the crosshair is active the mouse cursor is set invisible in the
target windows, since the cross is enough feedback and a cursor tends to
obscure the lines.  This is done with the WidgetCursor mechanism (see
L<Gtk2::Ex::WidgetCursor>) and so cooperates with other widget or
application uses of that.

The crosshair is drawn using xors in the widget window.  See
L<Gtk2::Ex::Xor> for notes on this.

=head1 FUNCTIONS

=over 4

=item C<< Gtk2::Ex::CrossHair->new (key => value, ...) >>

Create and return a new CrossHair object.  Optional key/value pairs set
initial properties as per C<< Glib::Object->new >>.  Eg.

    my $ch = Gtk2::Ex::CrossHair->new (widgets => [ $widget ],
                                       foreground => 'orange');

=item C<< $crosshair->start () >>

=item C<< $crosshair->start ($event) >>

=item C<< $crosshair->end () >>

Start or end crosshair display.

For C<start> if the optional C<$event> is a C<Gtk2::Gdk::Event::Button> then
the crosshair is active as long as that button is pressed, otherwise for a
keypress, omitted, or C<undef> then the crosshair is active until explicitly
stopped with an C<end> call.

=back

=head1 PROPERTIES

=over 4

=item C<active> (boolean)

True when the crosshair is to be drawn, moved, etc.  Turning this on or off
is the same as calling C<start> or C<end> above (except you can't pass a
button press event).

=item C<widgets> (array of C<Gtk2::Widget>)

An arrayref of widgets to draw on.  Often this will be just one widget, but
multiple widgets can be given to draw in them all at the same time.

=item C<widget> (C<Gtk2::Widget>)

A single widget to operate on.  The C<widget> and C<widgets> properties
access the same underlying set of widgets to operate on, you can set or get
whichever best suits.  But if there's more than one widget you can't get
from the single C<widget>.

=item C<foreground> (colour scalar, default undef)

The colour for the crosshair.  This can be

=over 4

=item *

A string colour name or #RGB form per C<< Gtk2::Gdk::Color->parse >>

=item *

A C<Gtk2::Gdk::Color> object.

=item *

C<undef> (the default) for the widget style C<fg> foreground colour (see
L<Gtk2::Style>).

=back

=back

=head1 SIGNALS

=over 4

=item moved (parameters: crosshair, widget, x, y, userdata)

Emitted when the crosshair moves to the given C<$widget> and X,Y coordinates
within that widget (widget relative coordinates).  C<$widget> is C<undef> if
the mouse moves outside any of the crosshair widgets.

It's worth noting a subtle difference in C<moved> reporting when a crosshair
is activated from a button or from the keyboard.  A button press causes an
implicit grab and all events are reported to that window.  C<moved> gives
that widget and an X,Y position possibly outside its window area
(eg. negatives).  But for a keyboard or programmatic start C<moved> reports
the widget currently containing the mouse, or C<undef> when not in any.
Usually the button press grab is good thing, it means a dragged button keeps
reporting about its original window.

=back

=head1 BUGS

C<no-window> widgets don't work properly, but instead should be put in a
C<Gtk2::EventBox> and that passed to the crosshair.

=head1 SEE ALSO

L<Gtk2::Ex::Lasso>, L<Gtk2::Ex::Xor>, L<Glib::Object>,
L<Gtk2::Ex::WidgetCursor>

=head1 HOME PAGE

L<http://www.geocities.com/user42_kevin/gtk2-ex-xor/index.html>

=head1 LICENSE

Copyright 2007, 2008 Kevin Ryde

Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

Gtk2-Ex-Xor is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
Gtk2-Ex-Xor.  If not, see L<http://www.gnu.org/licenses/>.

=cut
