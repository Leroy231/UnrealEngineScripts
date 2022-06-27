# Unreal Engine Scripts
Collection of scripts to help working with Unreal Engine.

# MassEntityProcessorsAndFragmentsToCsv.ps1

This script is useful for large UE5 projects that use the [MassEntity framework](https://docs.unrealengine.com/5.0/en-US/mass-entity-in-unreal-engine/), such as [City Sample](https://www.unrealengine.com/marketplace/en-US/product/city-sample). It produces a CSV which lists all processors and fragments used in the project, and their access modifiers.

## Example Usage
Example usage to copy CSV output to clipboard (make sure to use a valid path to .sln file):
```
MassEntityProcessorsAndFragmentsToCsv.ps1 -SlnPath D:\UE5\CitySample\CitySample.sln | Set-Clipboard
```

## Example Output

CSV in Google Sheets: https://docs.google.com/spreadsheets/d/1cV5LdfMd-Jj0PdczKeZLYpwrhCdmPPfa8gGXU_T9oQE/edit?usp=sharing

## Parameters

There are several optional parameters to the script:
- `-CppFileRegex`: A regex for which .cpp files to search for Mass Processor definitions
- `-CppFileRegexToIgnore`: A regex for files to ignore
- `-ProcessorNameRegexToIgnore`: A regex for Processor class names to ignore

For default values see the top of the script.

## Access Modifier Abbreviations

In the CSV the access modifiers are abbreviated as:
- R: read access
- W: write access
- N: no access

## Limitations

Currently the script has the following limitations:
- Does not have great error handling
- Relies on regex parsing of C++ code, which can be brittle
- Things like AddTagRequirement (tag requirements) or AddConstSharedRequirement (shared requirements) are not captured in the outputted CSV

If anyone wants to submit a PR for any of these I'll more than happily accept it.
