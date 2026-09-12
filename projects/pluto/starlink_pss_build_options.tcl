# Pure receiver build-option admission; sourcing this file changes no project,
# IP, environment, filesystem, clocks, or constraints. Integration is separate.
# Call BEFORE project creation, and again from the BD's independent admission:
#   set options [pss_resolve_build_options [array get ::env]]
# The returned dict has exactly rate_msps/profile/shared_xfft/realtime_xfft/
# boundary_stop. It is configuration intent, NOT evidence that a generated BD
# or synthesized receiver contains the selected feature or advertises its ABI.
# Later callers must set/read back CONFIG.ENABLE_BOUNDARY_STOP and independently
# verify the generated image. Unrelated environment entries are ignored.

proc pss_resolve_build_options {environment} {
  if {[catch {dict size $environment}]} {
    error "PSS build options require an environment dictionary"
  }
  set options [dict create]
  foreach {name field default} {
    STARLINK_PSS_RATE_MSPS rate_msps 15
    STARLINK_PSS_PROFILE profile full
    STARLINK_PSS_SHARED_XFFT shared_xfft 0
    STARLINK_PSS_REALTIME_XFFT realtime_xfft 0
    STARLINK_PSS_BOUNDARY_STOP boundary_stop 0
  } {
    set value $default
    if {[dict exists $environment $name]} {
      set value [dict get $environment $name]
    }
    dict set options $field $value
  }

  set rate [dict get $options rate_msps]
  set profile [dict get $options profile]
  set shared [dict get $options shared_xfft]
  set realtime [dict get $options realtime_xfft]
  set boundary [dict get $options boundary_stop]
  if {$rate ni {2.5 15 30 60}} {
    error "STARLINK_PSS_RATE_MSPS must be 2.5, 15, 30, or 60"
  }
  if {$profile ni {full detector-only paired-pilot acquisition-only acquisition-injection coarse25}} {
    error "unsupported STARLINK_PSS_PROFILE"
  }
  if {($profile eq "coarse25") != ($rate eq "2.5")} {
    error "coarse25 requires explicit STARLINK_PSS_RATE_MSPS=2.5; wider filters are not integrated"
  }
  foreach {name value} [list \
    STARLINK_PSS_SHARED_XFFT $shared \
    STARLINK_PSS_REALTIME_XFFT $realtime \
    STARLINK_PSS_BOUNDARY_STOP $boundary] {
    # Deliberately reject Tcl boolean aliases, whitespace and numeric aliases.
    if {$value ni {0 1}} {
      error "$name must be the literal 0 or 1"
    }
  }
  if {$profile eq "acquisition-injection" && $rate ne "15"} {
    error "acquisition-injection is qualified only at 15 MS/s"
  }
  if {$shared eq "1"} {
    # Match the existing full-project policy: an omitted rate must not silently
    # acquire experimental shared-mode authorization from the 15 MS/s default.
    if {![dict exists $environment STARLINK_PSS_RATE_MSPS] || $rate ne "15" ||
        ![dict exists $environment STARLINK_PSS_PROFILE] || $profile ne "paired-pilot"} {
      error "shared-XFFT requires explicit paired-pilot at 15 MS/s"
    }
  }
  if {$realtime eq "1" && $shared ne "1"} {
    error "realtime-XFFT requires explicit shared paired-pilot at 15 MS/s"
  }
  if {$boundary eq "1" && $shared ne "1"} {
    error "boundary-stop requires explicit shared paired-pilot at 15 MS/s"
  }
  # Boundary stop does not imply realtime. Shared non-realtime at explicit
  # 15 MS/s paired-pilot remains an admissible implementation configuration.
  return $options
}
