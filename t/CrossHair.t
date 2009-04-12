#!/usr/bin/perl

# Copyright 2008, 2009 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.


use strict;
use warnings;
use Gtk2::Ex::CrossHair;
use Test::More tests => 17;

my $want_version = 6;
cmp_ok ($Gtk2::Ex::CrossHair::VERSION, '>=', $want_version,
        'VERSION variable');
cmp_ok (Gtk2::Ex::CrossHair->VERSION,  '>=', $want_version,
        'VERSION class method');
{ ok (eval { Gtk2::Ex::CrossHair->VERSION($want_version); 1 },
      "VERSION class check $want_version");
  my $check_version = $want_version + 1000;
  ok (! eval { Gtk2::Ex::CrossHair->VERSION($check_version); 1 },
      "VERSION class check $check_version");
}
{
  my $cross = Gtk2::Ex::CrossHair->new;
  ok ($cross->VERSION  >= $want_version, 'VERSION objectmethod');
  ok (eval { $cross->VERSION($want_version); 1 },
      "VERSION object check $want_version");
  my $check_version = $want_version + 1000;
  ok (! eval { $cross->VERSION($check_version); 1 },
      "VERSION object check $check_version");
}

require Gtk2;
diag ("Perl-Gtk2 version ",Gtk2->VERSION);
diag ("Perl-Glib version ",Glib->VERSION);
diag ("Compiled against Glib version ",
      Glib::MAJOR_VERSION(), ".",
      Glib::MINOR_VERSION(), ".",
      Glib::MICRO_VERSION(), ".");
diag ("Running on       Glib version ",
      Glib::major_version(), ".",
      Glib::minor_version(), ".",
      Glib::micro_version(), ".");
diag ("Compiled against Gtk version ",
      Gtk2::MAJOR_VERSION(), ".",
      Gtk2::MINOR_VERSION(), ".",
      Gtk2::MICRO_VERSION(), ".");
diag ("Running on       Gtk version ",
      Gtk2::major_version(), ".",
      Gtk2::minor_version(), ".",
      Gtk2::micro_version(), ".");

# return an arrayref
sub leftover_fields {
  my ($widget) = @_;
  my @leftover = grep /Gtk2::Ex::CrossHair/, keys %$widget;
  if (@leftover) {
    my %leftover;
    @leftover{@leftover} = @{$widget}{@leftover}; # hash slice
    diag "leftover fields: ", explain \%leftover;
  }
  return \@leftover;
}

sub main_iterations {
  my $count = 0;
  while (Gtk2->events_pending) {
    $count++;
    Gtk2->main_iteration_do (0);
  }
  diag "main_iterations(): ran $count events/iterations\n";
}

sub show_wait {
  my ($widget) = @_;
  my $t_id = Glib::Timeout->add (10_000, sub {
                                   diag "Timeout waiting for map event\n";
                                   exit 1;
                                 });
  my $s_id = $widget->signal_connect (map_event => sub {
                                        Gtk2->main_quit;
                                        return 0; # propagate event
                                      });
  $widget->show;
  Gtk2->main;
  $widget->signal_handler_disconnect ($s_id);
  Glib::Source->remove ($t_id);
}


#-----------------------------------------------------------------------------

SKIP: {
  require Gtk2;
  Gtk2->disable_setlocale;  # leave LC_NUMERIC alone for version nums
  if (! Gtk2->init_check) { skip 'due to no DISPLAY available', 10; }


  # destroyed when weakened on unrealized
  {
    my $widget = Gtk2::Window->new ('toplevel');
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    my $weak_cross = $cross;
    require Scalar::Util;
    Scalar::Util::weaken ($weak_cross);
    $cross = undef;
    main_iterations();
    is ($weak_cross, undef, 'weaken unrealized - destroyed');
    is_deeply (leftover_fields($widget), [],
               'weaken unrealized - no CrossHair data left behind');
    $widget->destroy;
  }

  # destroyed when weakened on realized
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->realize;
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    my $weak_cross = $cross;
    Scalar::Util::weaken ($weak_cross);
    $cross = undef;
    is ($weak_cross, undef, 'weaken realized - destroyed');
    is_deeply (leftover_fields($widget), [],
               'weaken realized - no CrossHair data left behind');
    $widget->destroy;
  }

  # destroyed when weakened on active
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->set_size_request (100, 100);
    show_wait ($widget);

    # temporary warp to have mouse pointer within $widget
    my $display = $widget->get_display;
    my ($screen,$x,$y) = $display->get_pointer;
    my ($widget_x,$widget_y) = $widget->window->get_origin;
    $display->warp_pointer($widget->get_screen,$widget_x+50,$widget_y+50);

    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    $cross->start;
    # sync and iterate to make the cross draw and use its gc
    $display->sync; 
    main_iterations();

    my $weak_cross = $cross;
    Scalar::Util::weaken ($weak_cross);
    $cross = undef;
    main_iterations();
    is ($weak_cross, undef, 'weaken active - destroyed');
    is_deeply (leftover_fields($widget), [],
               'weaken active - no CrossHair data left behind');

    $widget->destroy;
    $display->warp_pointer($screen,$x,$y);
  }

  # start() emits "notify::active"
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->realize;
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    my $seen_notify = 0;
    $cross->signal_connect ('notify::active' => sub { $seen_notify = 1; });
    $cross->start;
    is ($seen_notify, 1, 'start() emits notify::active');
    $widget->destroy;
  }

  # end()emits "notify::active"
  {
    my $widget = Gtk2::Window->new ('toplevel');
    $widget->realize;
    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    $cross->start;
    my $seen_notify = 0;
    $cross->signal_connect ('notify::active' => sub { $seen_notify = 1; });
    $cross->end;
    is ($seen_notify, 1, 'end() emits notify::active');
    $widget->destroy;
  }

  # leftovers on changing widget, and switching to a widget without a common
  # ancestor with the previous
  {
    my $widget = Gtk2::Window->new ('toplevel');
    my $widget2 = Gtk2::Window->new ('toplevel');
    $widget->set_size_request (100, 100);
    show_wait ($widget);
    show_wait ($widget2);

    # temporary warp to have mouse pointer within $widget
    my $display = $widget->get_display;
    my ($screen,$x,$y) = $display->get_pointer;
    my ($widget_x,$widget_y) = $widget->window->get_origin;
    $display->warp_pointer($widget->get_screen,$widget_x+50,$widget_y+50);

    my $cross = Gtk2::Ex::CrossHair->new (widget => $widget);
    $cross->start;
    # sync and iterate to make the cross draw and use its gc
    $display->sync;
    main_iterations();

    $cross->set (widget => $widget2);
    ($widget_x,$widget_y) = $widget2->window->get_origin;
    $display->warp_pointer($widget2->get_screen,$widget_x+50,$widget_y+50);
    $display->sync;
    main_iterations();

    is_deeply (leftover_fields($widget), [],
               'change widget - no CrossHair data left behind');

    $cross->set (widgets => []);
    is_deeply (leftover_fields($widget2), [],
               'change to no widgets - no CrossHair data left behind');

    $widget->destroy;
    $widget2->destroy;
    $display->warp_pointer($screen,$x,$y);
  }

}

exit 0;
