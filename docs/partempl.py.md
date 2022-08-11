# `partempl.py`

`partempl.py` fills command templates with parameters using a simple DSL for file name manipulation.

The idea is that you create a template for a command you want to run (e.g. a read mapper), and fill that template using parameters from a globbing pattern or from a TSV table.

The templating syntax is inspired by [GNU Parallel replacement strings](https://www.gnu.org/software/parallel/parallel_tutorial.html#replacement-strings) but looks more like a hybrid of bash parameter expansion and sed syntax.
Nothing quite did everything that I needed as is, so it's a hybrid.


There are several options, but it's easiest to demonstrate before going into technical details.

First I'll generate some example files to demonstrate with...

```
mkdir dir1 dir2

touch {dir1,dir2}/{one,two,three}-{R1,R2}.fastq.gz
```

I'm using paired fastq reads as an example because it is a common use case for some of the grouping options supported.
Throughout this guide, we'll use a hypothetical command `map.sh` as an example.

`partempl.py` can take parameters as either a globbed pattern or a TSV table.
A basic command will look like:

```
partempl.py "template" *-glob.txt
# or
partempl.py --file params.tsv "template"
```

We'll demonstrate the globbing structure more because it's more complicated, and it's easier to translate commands to the table syntax later.

As a basic example, if you wanted to run a command for each input file using a globbing pattern:

```
partempl.py map.sh dir1/*.fastq.gz

# map.sh 'dir1/one-R1.fastq.gz'
# map.sh 'dir1/one-R2.fastq.gz'
# map.sh 'dir1/three-R1.fastq.gz'
# map.sh 'dir1/three-R2.fastq.gz'
# map.sh 'dir1/two-R1.fastq.gz'
# map.sh 'dir1/two-R2.fastq.gz'
```

In this case, we haven't used templating syntax at all, so `partempl.py` will just provide the parameters to the end of the "template" string (just like GNU parallel).
We could be more explicit about where the parameter should be provided using the template syntax.

```
partempl.py 'map.sh --infile {} --verbose' dir1/*.fastq.gz

# map.sh --infile dir1/one-R1.fastq.gz --verbose
# map.sh --infile dir1/one-R2.fastq.gz --verbose
# map.sh --infile dir1/three-R1.fastq.gz --verbose
# map.sh --infile dir1/three-R2.fastq.gz --verbose
# map.sh --infile dir1/two-R1.fastq.gz --verbose
# map.sh --infile dir1/two-R2.fastq.gz --verbose
```

Here the input file will be provided where `{}` is.

How about if we have multiple parameters to provide to the file?
Say we have some paired end fastq files that we want to provide to the same command.
Here we use [bash brace expansion](https://www.gnu.org/software/bash/manual/html_node/Brace-Expansion.html) in combination with the `--nparams` parameter.

Say we want to map both `R1` and `R2` files.

```
./patempl.py --nparams 2 map.sh dir1/*-{R1,R2}.fastq.gz

# map.sh 'dir1/one-R1.fastq.gz' 'dir1/one-R2.fastq.gz'
# map.sh 'dir1/three-R1.fastq.gz' 'dir1/three-R2.fastq.gz'
# map.sh 'dir1/two-R1.fastq.gz' 'dir1/two-R2.fastq.gz'
```

So we specified the pairs with the brace expansion `{R1,R2}`, and told the program that there are two parameters.
If we had three parameters we could simply use e.g. `{R1,R2,unpaired}` and `--nparams 3`.

Its worth looking at how the glob and braces actually expand.

```
echo dir1/*-{R1,R2}.fastq.gz
# dir1/one-R1.fastq.gz dir1/three-R1.fastq.gz dir1/two-R1.fastq.gz dir1/one-R2.fastq.gz dir1/three-R2.fastq.gz dir1/two-R2.fastq.gz
```

So here the brace expansion `{R1,R2}` will determine how the files are grouped.
And together with the wildcard `*`, the command expands to list all `-R1.fastq.gz` files then the `-R2.fastq.gz` files.
`partempl.py` relies on this ordering to associate the parameters with each other.
As long as the order is correct it will be fine, so you could just provide the list of files if you want. But if the order is out or the `--nparams` doesn't match the order properly, it will give you weird results.

Make sure that there are no spaces in the braces (or make sure to use quoting), as they won't expand as you might expect.
e.g.

```
echo dir1/*-{R1, R2}.fastq.gz
# dir1/*-{R1, R2}.fastq.gz  # in bash, in zsh this errors

echo dir1/*-{R1,' R2'}.fastq.gz
# dir1/one-R1.fastq.gz dir1/three-R1.fastq.gz dir1/two-R1.fastq.gz dir1/*- R2.fastq.gz
# This extra space will cause trouble too                               ^^^^
```

See the [bash brace expansion documentation](https://www.gnu.org/software/bash/manual/html_node/Brace-Expansion.html) for details.


Just like with one argument, you can customise how the parameters are provided to the command using the templating syntax.

```
partempl.py --nparams 2 'map.sh --in1 {0} --in2 {1}' dir1/*-{R1,R2}.fastq.gz

# map.sh --in1 dir1/one-R1.fastq.gz --in2 dir1/one-R2.fastq.gz
# map.sh --in1 dir1/three-R1.fastq.gz --in2 dir1/three-R2.fastq.gz
# map.sh --in1 dir1/two-R1.fastq.gz --in2 dir1/two-R2.fastq.gz
```

First we'll just note that instead of using `{}` to place the parameters, we must now use `{index}` to pick the correct parameter to add.
When there is one parameter `{}` is an alias for `{0}`, but with more than one it becomes ambiguous so `partempl.py` will raise and error.
Indexing is 0 based (start inclusive and end exclusive), just like python.


And with that we're ready to look at some of the extra template syntax.
Within the `{...}` blocks, we can provide commands to perform actions on the parameters.
Some basic ones are `d` which returns the directory name, `b` with returns the filename without the directory, and `e` which strips an extension off the end of the file.

Here i'll use the right strip `r` command to strip `-R1.fastq.gz` from the end of a filename, which we'll use to create an output `.bam` filename.

```
partempl.py --nparams 2 'map.sh --out "{0r/-R1.fastq.gz/}.bam" --r2 "{1}" --r1 "{0}"' dir1/*-{R1,R2}.fastq.gz

# map.sh --out "dir1/one.bam" --r2 "dir1/one-R2.fastq.gz" --r1 "dir1/one-R1.fastq.gz"
# map.sh --out "dir1/three.bam" --r2 "dir1/three-R2.fastq.gz" --r1 "dir1/three-R1.fastq.gz"
# map.sh --out "dir1/two.bam" --r2 "dir1/two-R2.fastq.gz" --r1 "dir1/two-R1.fastq.gz"
```

You can combine commands to perform more complex operations.
For example in the above example, we could also strip the directory name from the output file `{0dr/-R1.fastq.gz/}.bam`, which will create `one.bam` instead of `dir1/one.bam` etc.

Most of the above could be done with GNU parallel style syntax, but things here can get a bit more exotic when you use the array syntax.
We'll go into this in more detail later, but briefly `{@}` will give you access to all parameters associated with the command (e.g. `[dir1/one-R2.fastq.gz, dir1/one-R1.fastq.gz]`). We can perform operations on this array as well as the strings inside it.

Instead of using the right strip function `r` above, we could create an output filename based on the common prefix of all parameters with the `p` array function.

```
partempl.py --nparams 2 'map.sh --out "{@p}.bam" --r2 "{1}" --r1 "{0}"' dir1/*-{R1,R2}.fastq.gz

# map.sh --out "dir1/one-R.bam" --r2 "dir1/one-R2.fastq.gz" --r1 "dir1/one-R1.fastq.gz"
# map.sh --out "dir1/three-R.bam" --r2 "dir1/three-R2.fastq.gz" --r1 "dir1/three-R1.fastq.gz"
# map.sh --out "dir1/two-R.bam" --r2 "dir1/two-R2.fastq.gz" --r1 "dir1/two-R1.fastq.gz"
```

It's not quite the same, to actually get the same output filename (`dir1/one.bam` instead of `dir1/one-R.bam`) we'd have to an rstrip as well `{@pr/-R/}.bam`.
But hopefully you get the idea.


The array syntax becomes more useful when you need to group data.
Say you had to split a sequencing run over multiple flow cells, and you don't want to merge the fastq files before aligning so that you can get proper read group information.
You can group pairs by some kind of data in the glob to extract how the files should be combined.

In this case, i'm going to pretend that the directories we created earlier (`dir1` and `dir2`) contain common samples that should be grouped. I'll provide that dirname to the `--group` parameter.

```
partempl.py --nparams 2 --group '{0d}' 'map.sh --out "{0d}.bam" --r1 "{0@}" --r2 "{1@}"' */*-{R1,R2}.fastq.gz

# map.sh --out "dir1.bam" --r1 "dir1/one-R1.fastq.gz dir1/three-R1.fastq.gz dir1/two-R1.fastq.gz" --r2 "dir1/one-R2.fastq.gz dir1/three-R2.fastq.gz dir1/two-R2.fastq.gz"
# map.sh --out "dir2.bam" --r1 "dir2/one-R1.fastq.gz dir2/three-R1.fastq.gz dir2/two-R1.fastq.gz" --r2 "dir2/one-R2.fastq.gz dir2/three-R2.fastq.gz dir2/two-R2.fastq.gz"
```

So what has happened here is that we've said to group by the directory `{0d}`, which has grouped all of the `*R1*` into an array `{0@}` (and `*R2*` into `{1@}`).
By default when `partempl.py` has to output an array, it will join the elements with a space.
So because we enclosed the command block `{0@}` in quotes the substituted string is `"dir2/one-R1.fastq.gz dir2/three-R1.fastq.gz dir2/two-R1.fastq.gz"`.

We can also join arrays using the `j` command. So to join by commas instead:

```
partempl.py --nparams 2 --group '{0d}' 'map.sh --out "{0d}.bam" --r1 "{0@j/,/}" --r2 "{1@j/,/}"' */*-{R1,R2}.fastq.gz

# map.sh --out "dir1.bam" --r1 "dir1/one-R1.fastq.gz,dir1/three-R1.fastq.gz,dir1/two-R1.fastq.gz" --r2 "dir1/one-R2.fastq.gz,dir1/three-R2.fastq.gz,dir1/two-R2.fastq.gz"
# map.sh --out "dir2.bam" --r1 "dir2/one-R1.fastq.gz,dir2/three-R1.fastq.gz,dir2/two-R1.fastq.gz" --r2 "dir2/one-R2.fastq.gz,dir2/three-R2.fastq.gz,dir2/two-R2.fastq.gz"
```


OK. So the globbing patterns are good for when you have fairly regular files and easy globbing patterns, but sometimes it's easier to just provide a TSV file with your parameters already.

E.g. in the paired run option above, you could have a file `reads.tsv` like below:

```
dir1/one-R1.fastq.gz	dir1/one-R2.fastq.gz
dir1/three-R1.fastq.gz	dir1/three-R2.fastq.gz
dir1/two-R1.fastq.gz	dir1/two-R2.fastq.gz
dir2/one-R1.fastq.gz	dir2/one-R2.fastq.gz
dir2/three-R1.fastq.gz	dir2/three-R2.fastq.gz
dir2/two-R1.fastq.gz	dir2/two-R2.fastq.gz
```

Instead of having to match the brace expansion with the `--nparams` parameter etc, you can just directly pass the parameters as different columns.
And then you can run pretty much the same command as above, but indead of providing the `--nparams` and a glob, you can just specify this file to `--file` and it will take the parameters from the columns.

```
partempl.py --file read_pairs.tsv 'map.sh --out "{0d}.bam" --r1 {0} --r2 {1}'

# map.sh --out "dir1.bam" --r1 dir1/one-R1.fastq.gz --r2 dir1/one-R2.fastq.gz
# map.sh --out "dir1.bam" --r1 dir1/three-R1.fastq.gz --r2 dir1/three-R2.fastq.gz
# map.sh --out "dir1.bam" --r1 dir1/two-R1.fastq.gz --r2 dir1/two-R2.fastq.gz
# map.sh --out "dir2.bam" --r1 dir2/one-R1.fastq.gz --r2 dir2/one-R2.fastq.gz
# map.sh --out "dir2.bam" --r1 dir2/three-R1.fastq.gz --r2 dir2/three-R2.fastq.gz
# map.sh --out "dir2.bam" --r1 dir2/two-R1.fastq.gz --r2 dir2/two-R2.fastq.gz
```

You could even add extra metadata columns (e.g. FASTQ read groups) and use that as a grouping pattern, which you can just access and manipulate like you did with the files.


So there's a lot of flexibility in the system, and it will all automatically submit the appropriate number of jobs depending on grouping parameters etc.


## String commands

- `b` basename `partempl.py "{b}" dir/one.fastq.gz  # one.fastq.gz`
- `d` dirname `partempl.py "{d}" dir/one.fastq.gz  # dir`
- `e` strip extension `partempl.py "{e}" dir/one.fastq.gz  # dir/one.fastq`. Use it n times to strip n extensions `partempl.py "{ee}" dir/one.fastq.gz  # dir/one`
- `l` left strip `partempl.py "{l/di/}" dir/one.fastq.gz  # r/one.fastq.gz`
- `r` right strip `partempl.py "{r/q.gz/}" dir/one.fastq.gz  # dir/one.fast`
- `s` substitute `partempl.py "{s/one/two/}" dir/one.fastq.gz  # dir/two.fastq.gz`
- `c` cleave (it's split but `s` was taken). Returns an array. `partempl.py "{c/ne/}" dir/one.fastq.gz  # dir/o .fastq.gz`
- `o` or (it's default but `d` was taken, think `o`r).  `partempl.py "{s/.*// o/default/}" dir/one.fastq.gz  # default`. The `s` command returns an empty string, so `default` is given.
- `q` quote the string in single quotes `'` to avoid weird characters.  `partempl.py "{q}" dir/one.fastq.gz  # 'dir/one.fastq.gz'`

Note that `l`, `r`, `s`, and `c` also support python regular expression syntax. E.g. in the `o` example we used `s` to match a sequence of any character `.*` with an empty string. partempl.py "{l/.*\./}" dir/one.fastq.gz

Substitution (`s`) patterns are also how you would insert text to the beginning or end of a string, using the `^` or `$` special regex characters, which match the beginning and end of the string respectively.
e.g.

```
partempl.py "{s/^/howdy/}" dir/one.fastq.gz  # howdydir/two.fastq.gz
partempl.py "{s/$/howdy/}" dir/one.fastq.gz  # dir/two.fastq.gzhowdy
```

Note that if the final template replacement results in an empty string being returned, `partempl.py` will raise an error as empty strings can cause errors.
Probably the behaviour you're after in this case is to return an empty string in quotes, as bash will still interpret this as an empty string instead of just whitespace.
If you wish to suppress this error, you can provide the `o` command without the pattern boundaries at the very end of the command.
This will allow `partempl.py` to return an empty string.

`o` commands without pattern boundaries that are in the middle of the template block will still raise an error.

### alt command modes

`e`, `l`, `r`, and `q` all support an uppercase variant which affects the function of the command.
All other commands are case insensitive.

- `E` strips the extension greedily. `partempl.py "{E}" dir/one.fastq.gz  # dir/one`. So while `e` removes extensions one at a time (and you can use the command multiple times), `E` just automatically removes all extensions.
- `L` strips greedily from the left. This becomes important if using regular expressions. `partempl.py "{L/.*\./}" dir/one.fastq.gz  # gz`, compare with `partempl.py "{l/.*\./}" dir/one.fastq.gz  # fastq.gz`.
- `R` strips greedily from the right. `partempl.py "{R/\..*/}" dir/one.fastq.gz  # dir/one`, compare with `partempl.py "{r/\..*/}" dir/one.fastq.gz  # dir/one.fastq`.
- `Q` Uses backslash escaping instead of single quotes. Say your path had a space in it... `partempl.py "{q}" 'dir/on e.fastq.gz'  # dir/my\ data.fastq.gz` compare to `partempl.py "{q}" 'dir/on e.fastq.gz'  # 'dir/my data.fastq.gz'`.


### command pattern boundaries

Some of the commands take arguments from a pair of boundary characters.
In the above examples we've used `/` as this boundary character, as it's the standard one for regular expressions.
But if you had to match a literal `/` in the argument, you'd have to backslash escape it. Otherwise the pattern will pick up the wrong closing boundary character.
`partempl.py` also supports the use of characters `%&~` as boundary characters, so e.g. if you wanted to add a new directory to the filename, you could use `partempl.py "{s~dir/~nested/dirs/~}" dir/one.fastq.gz  # nested/dirs/one.fastq.gz`. No need to escape!
As long as all of the boundary characters are the same, any of those characters will work.


## Array commands

You can access the arrays using the `@` operator at the beginning of the template pattern.

```
# Single row, access all values in the row.
partempl.py --nparams 2 "{@}" dir/one.fastq.gz dir/two.fastq.gz
# dir/one.fastq.gz dir/two.fastq.gz

# Grouped row by directory name, each column is now an array, so we can access a column array like so.
partempl.py --nparams 2 --group "{0d}" "{1@}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz dir/four.fastq.gz
# dir/three.fastq.gz dir/four.fastq.gz

# Using @ without an index in a grouped row, flattens the columns into a single array.
partempl.py --nparams 2 --group "{0d}" "{1@}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz dir/four.fastq.gz
dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz dir/four.fastq.gz
```

- `:<int>` Indexing an array. Returns a string. `partempl.py --nparams 2 "{@:1}" dir/one.fastq.gz dir/two.fastq.gz  # dir/two.fastq.gz`
- `:<int>:<int>` Slicing an array. Leaving one of the ints empty (e.g. `::<int>` or `:<int>:` will replace the missing value with the start or end, respectively). `partempl.py --nparams 3 "{@:0:2}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz  # dir/one.fastq.gz dir/two.fastq.gz`
- `f` Filter the array by regular expression. `partempl.py --nparams 3 "{@f/o/}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz  # dir/one.fastq.gz dir/two.fastq.gz`, selects only matches containing an `o` character. Filter also supports a special match inversion flag `^` directly after `f` to return all elements that don't match the filter `partempl.py --nparams 3 "{@f^/o/}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz  # dir/three.fastq.gz`. Note that in this case, the returned value is still an array, but with a single element. People might be expecting `!` to negate matches, but bash treats `!` as a special character and it would be cumbersome to escape it all of the time. `^` is taken from the negation syntax in regular expression boxes e.g. `[^ab]` matches any character except `a` or `b`
- `p` Returns the common prefix of all elements in the array. Returns a string. `partempl.py --nparams 3 "{@p}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz  # dir/`
- `u` Get the unique values in the array. `partempl.py --nparams 3 "{@u}" dir/one.fastq.gz dir/two.fastq.gz dir/one.fastq.gz  # dir/one.fastq.gz dir/two.fastq.gz`.
- `j` Join the array using a string. Returns a string. `partempl.py --nparams 3 "{@j/,/}" dir/one.fastq.gz dir/two.fastq.gz dir/three.fastq.gz  # dir/one.fastq.gz,dir/two.fastq.gz,dir/three.fastq.gz`. Note that the default behaviour when returning an array is equivalend to `j/ /`.

All string commands except `c` (cleave/split) can also be used on arrays and are broadcast over all elements.

Note that `:<int>` (indexing), `p`, and `j` all return strings and array commands can no-longer be used on the output.
Conversely, the string `c` command will convert a string to an array, which enables the array commands.

Both `:<int>:<int>` (slicing) and `f` commands have the potential to return empty arrays which `partempl.py` will raise as an error as empty strings can cause unexpected behaviour in bash commands.
These commands both support a special version of the `o` (default) string command. If an `o` command is given immediately after a filter or slice and the command returns an empty array, `o` will return a 1 element array filled with the value given.
If you don't really want to provide a value, you can just use `o//` to create a single element array containing an empty string.

The same rules about returning empty strings also applies to returning arrays. If the joining of an array would result in an empty string being output, it will raise an error, which you can suppress with a terminal `o` as before (but probably you want to `q`uote it instead).
