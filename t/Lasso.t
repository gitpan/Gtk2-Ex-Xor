#!/usr/bin/perl

# Copyright 2008 Kevin Ryde

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
use Gtk2::Ex::Lasso;
use Test::More tests => 8;

ok ($Gtk2::Ex::Lasso::VERSION >= 4);
ok (Gtk2::Ex::Lasso->VERSION  >= 4);

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

sub main_iterations {
  my $count = 0;
  while (Gtk2->events_pending) {
    $count++;
    Gtk2->main_iteration_do (0);
  }
  print "main_iterations(): ran $count events/iterations\n";
}

sub show_wait {
  my ($widget) = @_;
  my $t_id = Glib::Timeout->add (10_000, sub {
                                   print "Timeout waiting for map event\n";
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

SKIP: {
  require Gtk2;
  if (! Gtk2->init_check) { skip 'due to no DISPLAY available', 6; }

  # return an arrayref
  sub leftover_fields {
    my ($widget) = @_;
    return [ grep /Gtk2::Ex::Lasso/, keys %$widget ];
  }


  # destroyed when weakened inactive
  {
    my $widget = Gtk2::Window->new ('toplevel');
    my $lasso = Gtk2::Ex::Lasso->new (widget => $widget);
    my $weak_lasso = $lasso;
    require Scalar::Util;
    Scalar::Util::weaken ($weak_lasso);
    $lasso = undef;
    main_iterations();
    is ($weak_lasso, undef, 'inactive Lasso weakened');
    is_deeply (leftover_fields($widget), [],
               'no Lasso data left behind from inactive');
    $widget->destroy;
  }

  # destroyed when weakened active
  {
    my $widget = Gtk2::Window->new ('toplevel');
    my $lasso = Gtk2::Ex::Lasso->new (widget => $widget);
    show_wait ($widget);
    $lasso->start;
    my $weak_lasso = $lasso;
    Scalar::Util::weaken ($weak_lasso);
    $lasso = undef;
    is ($weak_lasso, undef, 'active Lasso weakened');
    is_deeply (leftover_fields($widget), [],
               'no Lasso data left behind from active');
    $widget->destroy;
  }

  # start() emits "notify::active"
  {
    my $widget = Gtk2::Window->new ('toplevel');
    show_wait ($widget);
    my $lasso = Gtk2::Ex::Lasso->new (widget => $widget);
    my $seen_notify = 0;
    $lasso->signal_connect ('notify::active' => sub { $seen_notify = 1; });
    $lasso->start;
    is ($seen_notify, 1);
    $widget->destroy;
  }

  # end() emits "notify::active"
  {
    my $widget = Gtk2::Window->new ('toplevel');
    show_wait ($widget);
    my $lasso = Gtk2::Ex::Lasso->new (widget => $widget);
    $lasso->start;
    my $seen_notify = 0;
    $lasso->signal_connect ('notify::active' => sub { $seen_notify = 1; });
    $lasso->end;
    is ($seen_notify, 1);
    $widget->destroy;
  }
}

exit 0;
