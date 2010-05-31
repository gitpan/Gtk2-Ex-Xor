# Copyright 2007, 2008, 2009, 2010 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3, or (at your option) any
# later version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.

package Gtk2::Ex::Xor;
use 5.008;
use strict;
use warnings;
use Carp;
use Gtk2;

# uncomment this to run the ### lines
#use Smart::Comments;

our $VERSION = 10;

sub get_gc {
  my ($widget, $fg_color, @params) = @_;

  my $xor_bg_color = $widget->Gtk2_Ex_Xor_background;
  my $colormap = $widget->get_colormap;

  if (! defined $fg_color) {
  STYLE:
    $fg_color = $widget->get_style->fg ($widget->state);

  } else {
    if (ref $fg_color) {
      $fg_color = $fg_color->copy;
    } else {
      my $str = $fg_color;
      $fg_color = Gtk2::Gdk::Color->parse ($str);
      if (! $fg_color) {
        carp "Gtk2::Gdk::Color->parse() cannot parse '$str' (fallback to style foreground)";
        goto STYLE;
      }
    }
    # a shared colour alloc is friendlier to pseudo-colour visuals, but if
    # the rest of gtk is using the rgb chunk anyway then may as well do the
    # same
    $colormap->rgb_find_color ($fg_color);
  }

  ### pixels: sprintf "fg %#x bg %#x xor %#x\n", $fg_color->pixel, $xor_bg_color->pixel, $fg_color->pixel ^ $xor_bg_color->pixel
  my $xor_color = Gtk2::Gdk::Color->new
    (0,0,0, $fg_color->pixel ^ $xor_bg_color->pixel);

  my $window = $widget->Gtk2_Ex_Xor_window;
  my $depth = $window->get_depth;
  return Gtk2::GC->get ($depth, $colormap,
                        { function   => 'xor',
                          foreground => $xor_color,
                          background => $xor_color,
                          @params
                        });
}

sub _event_widget_coords {
  my ($widget, $event) = @_;

  # Do a get_pointer() to support 'pointer-motion-hint-mask'.
  # Maybe should use $display->get_state here instead of just get_pointer,
  # but crosshair and lasso at present only work with the mouse, not an
  # arbitrary input device.
  if ($event->can('is_hint') && $event->is_hint) {
    return $widget->get_pointer;
  }

  my $x = $event->x;
  my $y = $event->y;
  my $eventwin = $event->window;
  if ($eventwin != $widget->window) {
    my ($wx, $wy) = $eventwin->get_position;
    ### subwindow offset: "$wx,$wy"
    $x += $wx;
    $y += $wy;
  }
  return ($x, $y);
}

sub _ref_weak {
  my ($weak_self) = @_;
  require Scalar::Util;
  Scalar::Util::weaken ($weak_self);
  return \$weak_self;
}


#------------------------------------------------------------------------------
# background colour hacks

# default is from the widget's Gtk2::Style, but with an undocumented
# 'Gtk2_Ex_Xor_background' as an override
#
sub Gtk2::Widget::Gtk2_Ex_Xor_background {
  my ($widget) = @_;
  if (exists $widget->{'Gtk2_Ex_Xor_background'}) {
    return $widget->{'Gtk2_Ex_Xor_background'};
  }
  return $widget->Gtk2_Ex_Xor_background_from_style;
}

# "bg" is the background for normal widgets
sub Gtk2::Widget::Gtk2_Ex_Xor_background_from_style {
  my ($widget) = @_;
  return $widget->get_style->bg ($widget->state);
}

# "base" is the background for text-oriented widgets like Gtk2::Entry and
# Gtk2::TextView.  TextView has multiple windows, so this is the colour
# meant for the main text window.
#
# GooCanvas uses the "base" colour too.  Dunno if it thinks of itself as
# text oriented or if white in the default style colours seemed better.
#
sub Gtk2::Entry::Gtk2_Ex_Xor_background_from_style {
  my ($widget) = @_;
  return $widget->get_style->base ($widget->state);
}
*Gtk2::TextView::Gtk2_Ex_Xor_background_from_style
  = \&Gtk2::Entry::Gtk2_Ex_Xor_background_from_style;
*Goo::Canvas::Gtk2_Ex_Xor_background_from_style
  = \&Gtk2::Entry::Gtk2_Ex_Xor_background_from_style;

# For Gtk2::Bin subclasses such as Gtk2::EventBox, look at the child's
# background if there's a child and if it's a no-window widget, since that
# child is what will be xored over.
#
# Perhaps this should be only some of the Bin classes, like Gtk2::Window,
# Gtk2::EventBox and Gtk2::Alignment.
{
  package Gtk2::Bin;
  sub Gtk2_Ex_Xor_background {
    my ($widget) = @_;
    # same override as above ...
    if (exists $widget->{'Gtk2_Ex_Xor_background'}) {
      return $widget->{'Gtk2_Ex_Xor_background'};
    }
    if (my $child = $widget->get_child) {
      if ($child->flags & 'no-window') {
        return $child->Gtk2_Ex_Xor_background;
      }
    }
    return $widget->SUPER::Gtk2_Ex_Xor_background;
  }
}


#------------------------------------------------------------------------------
# window choice hacks

# normal "->window" for most widgets
*Gtk2::Widget::Gtk2_Ex_Xor_window = \&Gtk2::Widget::window;

# for Gtk2::Layout must draw into its "bin_window"
*Gtk2::Layout::Gtk2_Ex_Xor_window = \&Gtk2::Layout::bin_window;

sub Gtk2::TextView::Gtk2_Ex_Xor_window {
  my ($textview) = @_;
  return $textview->get_window ('text');
}

# GtkEntry has a window and then within that a subwindow just 4 pixels
# smaller in height.  The latter is what it draws on.
#
# The following code as per Gtk2::Ex::WidgetCursor.  Since the subwindow
# isn't a documented feature check that it does, in fact, exist.
#
# The alternative would be "include inferiors" on the xor gc's.  But that'd
# probably cause problems on windowed widget children, since expose events
# in them wouldn't be seen by the parent's expose to redraw the
# crosshair/lasso/etc.
#
sub Gtk2::Entry::Gtk2_Ex_Xor_window {
  my ($widget) = @_;
  my $win = $widget->window || return undef; # if unrealized
  return ($win->get_children)[0] # first child
    || $win;
}

# GooCanvas draws on a subwindow too, also undocumented it seems
# (there's a tmp_window too, but that's only an overlay suppressing some
# expose events or something at selected times)
*Goo::Canvas::Gtk2_Ex_Xor_window = \&Gtk2::Entry::Gtk2_Ex_Xor_window;

1;
__END__

=head1 NAME

Gtk2::Ex::Xor -- shared support for drawing with XOR

=head1 DESCRIPTION

This is support code shared by C<Gtk2::Ex::CrossHair> and
C<Gtk2::Ex::Lasso>.

Both those add-ons draw using an "xor" onto the pixels in a widget (hence
the dist name), using a value that flips between the widget background and
the cross or lasso line colour.  Drawing like this is fast and portable,
though doing it as an add-on can potentially clash with what the widget does
natively.

=over 4

=item *

A single dominant background colour is assumed.  Often shades of grey or
similar will end up with a contrasting line but there's no guarantee of
that.

=item *

The background colour is taken from the widget C<Gtk2::Style> "bg" for
normal widgets, or from "base" for text widgets C<Gtk2::Entry> and
C<Gtk2::TextView>.  C<Goo::Canvas> is recognised as using "base" too.

=item *

Expose events are watched and xoring redone, though it assumes the widget
will redraw only the exposed region, as opposed to a full window redraw.
Clipping in a redraw is usually what you want, especially if the display
might not have the X double-buffering extension.

=item *

For multi-window widgets it's necessary to figure out which subwindow is the
one to draw on.  The xoring recognises the "bin" window of C<Gtk2::Layout>
(which includes C<Gnome2::Canvas>), the "text" subwindow of
C<Gtk2::TextView>, and the secret subwindows of C<Gtk2::Entry> and
C<Goo::Canvas>.

=item *

The SyncCall mechanism is used to protect against flooding the server with
more drawing than it can keep up with.  Each motion event would only result
in a few drawing requests, but it's still easy to overload the server if it
sends a lot of motions or if it's not very fast at drawing wide lines.  The
effect of SyncCall is to delay further drawing until hearing back from the
server that the previous has completed.

=back

=head1 SEE ALSO

L<Gtk2::Ex::CrossHair>, L<Gtk2::Ex::Lasso>

=head1 HOME PAGE

L<http://user42.tuxfamily.org/gtk2-ex-xor/index.html>

=head1 LICENSE

Copyright 2007, 2008, 2009, 2010 Kevin Ryde

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

#
# Not sure about describing this yet:
#
# =head1 SYNOPSIS
# 
#  use Gtk2::Ex::Xor;
#  my $colour = $widget->Gtk2_Ex_Xor_background;
# 
# =head1 FUNCTIONS
# 
# =over 4
# 
# =item C<< $widget->Gtk2_Ex_Xor_background() >>
# 
# Return a C<Gtk2::Gdk::Color> object, with an allocated pixel value, which is
# the background to XOR against in C<$widget>.
# 
# =back
# 
# =head1 SEE ALSO
# 
# L<Gtk2::Ex::CrossHair>, L<Gtk2::Ex::Lasso>
