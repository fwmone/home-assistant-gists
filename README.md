This repository is a curated collection of small, focused building blocks for Home Assistant.

It contains links, snippets, helper scripts, templates that emerged from real-world usage — often as part of Medium articles, experiments, or iterative refinements of a larger Home Assistant setup.

The common theme is practicality:
things that solved a concrete problem, improved robustness or performance, or helped reduce complexity — but did not warrant a full standalone repository on their own.

# Table of Contents
- [Table of Contents](#table-of-contents)
- [Overview](#overview)
  - [What you’ll find here](#what-youll-find-here)
  - [What this repository is *not*](#what-this-repository-is-not)
  - [Compatibility \& Stability](#compatibility--stability)
- [Hands-on experience blog: Medium articles \& background](#hands-on-experience-blog-medium-articles--background)
  - [Overview of the articles](#overview-of-the-articles)
- [Scripts](#scripts)
  - [immich\_sync\_favorites](#immich_sync_favorites)
    - [What it does](#what-it-does)
    - [Intended use case](#intended-use-case)
    - [Home Assistant integration](#home-assistant-integration)
    - [Configuration overview](#configuration-overview)
    - [Automation](#automation)
    - [Notes \& limitations](#notes--limitations)
    - [Why this exists](#why-this-exists)
- [License](#license)
- [Final note](#final-note)


# Overview
## What you’ll find here

- YAML snippets (templates, sensors, automations)
- Small helper scripts (Python, shell)
- Configuration patterns extracted from real installations
- Companion material for Medium articles and blog posts
- Experiments related to performance, energy efficiency, or long-term stability

Some of these pieces are intentionally narrow in scope.
They are meant to be understood, adapted, and integrated — not installed blindly.

## What this repository is *not*

- Not a polished “one-click” solution repository  
- Not a replacement for well-maintained official or HACS integrations  
- Not guaranteed to be production-ready for every setup  

Think of this repo as a **toolbox**, not a product.

## Compatibility & Stability

Unless stated otherwise:
- Snippets are tested against recent Home Assistant Core versions.
- APIs, internals, and behaviors may change.
- Use at your own discretion and adapt as needed.

If something breaks due to upstream changes, that is usually intentional transparency rather than neglect.

# Hands-on experience blog: Medium articles & background

Many of the ideas and snippets in this repository originate from a personal article series on Medium. The series is based on hands-on experience with Smart Home systems and Home Assistant in daily use — not in a lab, demo environment, or short-term experiment. No sponsoring, no ads.

The guiding goal throughout my smart home journey was simple:
to build a solution that feels natural, visually coherent, and genuinely helpful —
without being intrusive, overwhelming, or constantly demanding attention.

Instead of chasing features for their own sake, the focus is on:
- calm and intentional automation,
- interfaces that integrate seamlessly into everyday life,
- and systems that remain understandable and maintainable over time.

In the articles, I write about very concrete experiences:
what worked well,
what turned out to be brittle or over-engineered,
and what I would approach differently today if starting from scratch.

The writing is opinionated, but grounded.
If something exists here, it exists because it proved useful — or because it taught a lesson worth sharing.

## Overview of the articles
**1. [Smart Home Without the Show Effect](https://medium.com/@fwmone/smart-home-without-the-show-effect-c34834fe6855) / [Smart Home ohne Showeffekt](https://medium.com/@fwmone/smart-home-ohne-showeffekt-b1bff655c90a)**

A case for a restrained smart home that blends seamlessly into everyday life, provides real value, and does not constantly demand attention.

**2. [Smart Home Retrofit in Practice: Preparing and Wiring Light Switches Properly](https://medium.com/@fwmone/smart-home-retrofit-in-practice-preparing-and-wiring-light-switches-properly-96abdcfa5800) / [Smart-Home-Nachrüstung in der Praxis: Lichtschalter richtig vorbereiten und verdrahten](https://medium.com/@fwmone/smart-home-nachr%C3%BCstung-in-der-praxis-lichtschalter-richtig-vorbereiten-und-verdrahten-712aa68263de)**

This article demonstrates how existing lighting installations can be upgraded with smart home actuators in a clean and future-proof way, with an emphasis on safety, maintainability, and daily use.

**3. [Finding the Right Smart Home Hub: Alexa, FRITZ!Box, Homey, or Home Assistant?](https://medium.com/@fwmone/finding-the-right-smart-home-hub-alexa-fritz-box-homey-or-home-assistant-714da6c04e07) / [Smart-Home-Zentrale finden: Alexa, FRITZ!Box, Homey oder Home Assistant?](https://medium.com/@fwmone/smart-home-zentrale-finden-alexa-fritz-box-homey-oder-home-assistant-cc185015f85a)**

A hands-on comparison of common smart home hubs, focusing on real-world usability, integration depth, and long-term control rather than marketing promises.

**4. [Valuable Basics for Your Home Assistant Smart Home](https://medium.com/@fwmone/valuable-basics-for-your-home-assistant-smart-home-c9133ea8a754) / [Wertvolle Basics für dein Home Assistant-Smart-Home](https://medium.com/@fwmone/basics-f%C3%BCr-dein-home-assistant-smart-home-0530d8b68e6b)**

This article outlines the core principles that make a Home Assistant smart home stable, comprehensible, and genuinely useful in the long run — beyond gimmicks and feature overload.

# Scripts
## immich_sync_favorites

`immich_sync_favorites` is a small helper script that synchronizes favorite images from an Immich instance into a Home Assistant–managed environment — optimized for e-ink picture frames using [eink-optimize](https://github.com/fwmone/eink-optimize).

The script was developed out of practical use, not as a generic downloader.
Its purpose is to reliably bridge three worlds:

- Immich as a photo source and curation tool  
- Home Assistant as the orchestration layer  
- E-ink devices (Bloomin8, PaperlessPaper) with very specific rendering constraints  

### What it does

- Queries Immich for all **favorite images** via the metadata search API (paginated)
- Downloads originals only when required
- Optimizes images via an external optimization service [eink-optimize](https://github.com/fwmone/eink-optimize).
- Generates device-specific output variants:
  - JPEGs for Bloomin8 frames
  - PNGs for PaperlessPaper frames
- Keeps local directories in sync by removing files that are no longer favorites
- Exposes a simple status file for monitoring and automations

The script is designed to be:
- idempotent (safe to run repeatedly),
- conservative with network and storage usage,
- and predictable in long-term operation.

### Intended use case

This script is **not** meant as a general Immich export tool.

It is intended for setups where:
- favorites are curated manually in Immich,
- images are displayed passively (e.g. wall frames, ambient displays),
- and visual calmness, stability, and low maintenance matter more than immediacy.

Typical execution is automated via Home Assistant (e.g. nightly or a few times per day).

### Home Assistant integration

The script is usually invoked via a `shell_command` in `configuration.yaml`, with required configuration passed as environment variables:

```yaml
shell_command:
  immich_sync_favorites: >-
    /bin/bash -c 'IMMICH_BASE="http://immich.local:2283"
    EPDOPTIMIZE="http://eink-optimize.local:3030/optimize"
    HOMEASSISTANT_PUBLIC_ADDRESS="https://homeassistant.example.com"
    DEST_DIR_ORIGINALS="/config/www/picture-frames/originals"
    PUBLISH_DIR="/local/picture-frames/originals"
    DEST_DIR_BLOOMIN8="/media/picture-frames/bloomin8"
    DEST_DIR_PAPERLESSPAPER="/media/picture-frames/paperlesspaper"    
    IMMICH_API_KEY="{{ secrets.immich_api_key }}"
    nohup /config/scripts/immich_sync_favorites.sh
    >/config/scripts/immich_sync_favorites.log 2>&1 &'
```

In `secrets.yaml`:

```yaml
immich_api_key: "YOUR_IMMICH_API_KEY"
```

### Configuration overview

The script expects the following environment variables:

|variable|value|
|--------|-----|
|IMMICH_BASE|Base URL of the Immich instance|
|IMMICH_API_KEY|API key with access to the Immich search and asset endpoints|
|HOMEASSISTANT_PUBLIC_ADDRESS|Publicly reachable Home Assistant base URL used by the optimizer service. Can be your internal Home Assistant address if einkoptimize is also locally hosted|
|EINKOPTIMIZE|Endpoint of [eink-optimize](https://github.com/fwmone/eink-optimize)|

**Target directories**

All filesystem paths are configurable and must be writable by Home Assistant:

|variable|value|
|--------|-----|
|DEST_DIR_ORIGINALS|Temporary storage for downloaded original images|
|PUBLISH_DIR|Public path used to expose originals to the optimizer service|
|DEST_DIR_BLOOMIN8|Target directory for Bloomin8-optimized JPEG images|
|DEST_DIR_PAPERLESSPAPER|Target directory for PaperlessPaper-optimized PNG images|

### Automation
In an automation, usage is as simple as that

```yaml
actions:
  - action: shell_command.immich_sync_favorites
```

I enhanced it by an error handling notification and "last sync" sensor like this:

```yaml
alias: "Bloomin8 / paperlesspaper: Immich Favoriten Sync ausführen und Fehler melden"
description: ""
triggers:
(...)
conditions:
(...)
actions:
  - action: shell_command.immich_sync_favorites
  - target:
      entity_id: sensor.immich_sync_raw
    action: homeassistant.update_entity
  - delay: "00:00:01"
  - choose:
      - conditions:
          - condition: state
            entity_id: sensor.immich_sync_status
            state: ok
        sequence:
          - action: input_datetime.set_datetime
            target:
              entity_id: input_datetime.letzte_synchronisation_immich_favoriten
            data:
              datetime: "{{ now().strftime('%Y-%m-%d %H:%M:%S') }}"
      - conditions:
          - condition: state
            entity_id: sensor.immich_sync_status
            state: error
        sequence:
          - action: script.alert_senden
            data:
              tag: alert_regensensor_batterie
              title: Immich Sync fehlgeschlagen 📸
              message: |
                {{ states('sensor.immich_sync_error') }}
mode: single
```

`script.alert_senden` is a notification script that I will publish soon.

### Notes & limitations

- The script intentionally avoids additional dependencies like jq
- API changes in Immich may require adjustments
- Error handling is pragmatic and optimized for unattended execution
- This is a focused tool — adapt it to your setup rather than expecting universal defaults

### Why this exists

This script exists because it solved a real problem in a real home:
keeping curated photos in sync across e-ink displays without constant attention, UI clutter, or fragile workflows.

If it fits your setup, use it.
If not, treat it as a reference — or a starting point.

# License

Unless noted otherwise, content in this repository is provided under the MIT License.

Feel free to use, adapt, and remix — attribution is appreciated but not required.

# Final note

If you find something useful here, great.
If it sparks a better idea in your own setup, even better.
I welcome your ideas and improvements.

That’s the point.
