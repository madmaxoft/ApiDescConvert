# ApiDescConvert
Script to convert APIDesc in Cuberite to new format. This is used for a one-time conversion from the old format:
```lua
Params = "string, number, {{cWorld|World}}"
```

into the new format:
```lua
Params =
{
  {Type = "string"},
  {Type = "number"},
  {Type = "cWorld", Name = "World"},
}
```

This conversion will be followed by a manual cleanup, all to implement https://github.com/cuberite/cuberite/issues/3375 .
