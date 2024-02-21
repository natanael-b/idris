#!/bin/lua5.4

function Print_usage()
    print [[

 Idris v0.1
--------------------------------------------------------------------------------

Turn natural language inputs into scriptable commands

Syntax:
~~~~~~~~
  lua5.4 idris.lua --lang=<language code> --database=<database with commands  \
    'input 1' 'input 2' 'input 3' 'input 4'...

Test demonstration:
~~~~~~~~~~~~~~~~~~~
  lua5.4 idris.lua --lang=pt_BR --database=demonstration         \
    'crie o arquivo teste.txt, coloque nele a frase Olá Mundo!'

]]
  os.exit(0)
end

local prefix = ""
local command_termination = "\n"
local enclose = ""

do
    local lang, database, env_lang
    env_lang = os.getenv("LANG")
    env_lang = env_lang and env_lang:gsub("%.UTF%-8", "") or "C"

    for i, argument in ipairs(arg) do
        if lang == nil and tostring(argument):sub(1, 7) == "--lang=" then
            lang = tostring(argument):sub(8, -1)
            arg[i] = false
            goto _continue
        end

        if database == nil and tostring(argument):sub(1, 11) == "--database=" then
            database = tostring(argument):sub(12, -1)
            arg[i] = false
            goto _continue
        end

        if prefix == nil and tostring(argument):sub(1, 9) == "--prefix=" then
            prefix = tostring(argument):sub(10, -1)
            arg[i] = false
            goto _continue
        end

        if argument == "--shell-output" then
            command_termination = "; "
            arg[i] = false
            goto _continue
        end

        if argument == "--interactive" then
            interactive = true
            arg[i] = false
            goto _continue
        end

        if argument == "-h" or argument == "--help" then
            Print_usage()
        end
        ::_continue::
    end

    if #arg == 0 then
        Print_usage()
    end

    local f_lang = io.open("languages/" .. env_lang .. ".lua", "r")
    if f_lang then
        lang = lang or env_lang
        f_lang:close()
    end

    if lang == nil then
        print "Missing --lang= parameter and env LANG doesn't have a compatible language"
        os.exit(1)
    end

    if database == nil then
        print "Missing --database= parameter"
        os.exit(1)
    end

    require("languages." .. lang)
    require("databases." .. lang .. "." .. database)
end

Words = {}

function Split(input)
    Words = {}

    for word in tostring(input):gmatch("[^ ]*") do
        word = word == "" and " " or word

        if word:sub(-1,-1) == "," then
            word = word:sub(1,-2)
            Words[#Words+1] = word
            Words[#Words+1] = ","
        else
            Words[#Words+1] = word
        end
    end
end

function Find_DB_key(current_index,list)
    if list == nil then return nil end

    local avaialable_nouns= {}

    for noun in pairs(list) do
        if type(noun) == "string" then
            local _,spaces_count = noun:gsub(" ","")
            avaialable_nouns[spaces_count] = avaialable_nouns[spaces_count] or {}
            avaialable_nouns[spaces_count][#avaialable_nouns[spaces_count]+1] = noun

            avaialable_nouns.max_spaces = avaialable_nouns.max_spaces or 0
            avaialable_nouns.max_spaces = avaialable_nouns.max_spaces > spaces_count and avaialable_nouns.max_spaces or spaces_count
        end
    end

    for i = (avaialable_nouns.max_spaces or -1), 1, -1 do
        for _, noun in ipairs(avaialable_nouns[i]) do
            local words_combined = Words[current_index]
            for _ = 1, i, 1 do
                words_combined = words_combined.." "..(Words[current_index+1] or "")
            end

            if noun == words_combined then
                for _ = 1, i, 1 do
                    Words[current_index+1] = false
                end

                return list[words_combined]
            end
        end
    end

    return nil
end

State = {}
local has_input = false

::process::
for i, input in ipairs(arg) do
    if input == false then goto skip_input end

    has_input = true

    Split((prefix or "")..input.." \0")
    local current_list = {}
    local current_fallback = {}

    for _, word in ipairs(Words) do
        if word == false then goto continue end

        ::start::

        State.max_index = State.max_index or 0
        State.current_list_index = State.current_list_index or 0
        State.max_index = State.max_index > State.current_list_index and State.max_index or State.current_list_index


        if State.verb == nil then
            Words[_] = Language.infinitive(word:lower())

            State.verb = Find_DB_key(_,DB) or DB[Words[_]] or DB[word]

            if State.verb then
                State.arguments = State.arguments or {}
                State.arguments_fallback = State.arguments_fallback or {}

                State.arguments[1] = {}
                State.arguments_fallback[1] = State.arguments_fallback[1] or {}

                State.current_list_index = 1

                current_list = State.arguments[1]
                current_fallback = State.arguments_fallback[1]
            end
            goto continue
        end

        if State.noun == nil then
            State.noun = Find_DB_key(_,State.verb) or State.verb[word]

            if State.noun then
                if Language.prepositions[current_list[#current_list]] then
                    table.remove(current_list,#current_list)
                end

                State.old_noun_word = State.noun_word
                State.noun_word = word

                State.arguments[2] = {}
                State.arguments_fallback[2] = State.arguments_fallback[2] or {}

                State.current_list_index = 2

                current_list = State.arguments[2]
                current_fallback = State.arguments_fallback[2]
                goto continue
            end
        end

        if word == "\0" or (Language.list_separators[word] and DB[Language.infinitive(Words[_+1]:lower())]) then
            
            -- Fix using Verb+Pronouns+Noun part 1 (must be here)
            local remove_second_arg = false
            local second_arg = ""
            if State.verb[current_list[1]] and (State.noun == State.verb[current_list[1]]) then
                second_arg = current_list[1]
                table.remove(current_list,1)
                remove_second_arg = true
            end

            if State.noun == nil and (Language.prepositions[State.arguments[1][1]] or Language.pronouns[State.arguments[1][1]]) then
                table.remove(State.arguments[1],1)
            end

            local arguments = {}

            -- Allow implicit personal pronoun
            State.noun = State.noun or State.verb[State.noun_word]

            -- Fill the arguments table
            for j = 1, State.max_index, 1 do
                arguments[#arguments+1] = table.concat(State.arguments[j] or {}," ")
            end

            -- Fix empty 2nd argument
            if State.current_list_index == 2 and #(State.arguments[2] or {}) == 0 then
                arguments[2] = arguments[1]
            end

            -- Fix empty arguments using the fallbacks
            for j = 2, State.max_index, 1 do
                if #(State.arguments[j] or {}) == 0 then
                    arguments[j] = table.concat((State.arguments_fallback[j] or {})," ")
                end
            end

            if (#(State.arguments[2] or {}) == 0) and State.old_noun_word ~= State.noun_word and #(State.arguments[1] or {}) ~= 0 then
                arguments[2] = arguments[1]
                goto build_cmd
            end

            -- Fix empty arguments using the next argument
            for j = 2, State.max_index, 1 do
                if (#(State.arguments[j] or {}) == 0) and State.old_noun_word ~= State.noun_word and #(State.arguments[j+1] or {}) ~= 0 then
                    arguments[j] = arguments[j+1]
                end
            end

            -- Fix using Verb+Pronouns+Noun part 1 (must be here)
            if remove_second_arg then
                arguments[2] = arguments[2]:gsub(" "..second_arg.."$","")
            end

            -- Allow implicit pronouns
            if (State.noun or State.verb)[0] == nil then
                local words = {}
                for _word in tostring(arguments[1]):gmatch("[^ ]*") do
                    _word = _word == "" and " " or _word
                    words[#words+1] = _word
                end
                local noun_fallback = ""
                for j = 1, #words, 1 do
                    noun_fallback = noun_fallback == "" and words[j] or noun_fallback.." "..words[j]
                    if State.noun[noun_fallback] then
                        for _ = 1, j, 1 do table.remove(words,1) end
                        State.noun = State.noun[noun_fallback]
                        break
                    end
                end
            end

            ::build_cmd::

            local cmd = tostring((State.noun or State.verb)[0])
            for j = 1, State.max_index, 1 do
                cmd = cmd:gsub("\0{"..j.."}",arguments[j])
            end
            -- Patterns ends with \255, so we not add termination
            if cmd:sub(-1,-1) ~= "\255" then
                io.write(cmd..command_termination..(word == "\0" and enclose or ""))
            else
                cmd = cmd:sub(1,-2)
                enclose = cmd:gsub("^.*\2","")
                cmd = cmd:gsub("\2.*","")
                io.write(cmd)
            end

            State.noun = nil
            State.verb = nil

            if word == "\0" and not interactive then
                State = {}
            end

            goto continue
        end

        if Language.personal_pronoun[word] then
            word = State.noun_word
            goto start
        end

        if Language.pronouns[word] and State.verb[State.noun_word] and not Language.personal_pronoun[Words[_-1]] then
            word = State.noun_word or word
            goto start
        end

        if State.verb[State.noun_word] == nil and Language.prepositions[Words[_+1]] then
            goto continue
        end

        if State.noun then
            local sub_noun = Find_DB_key(_,State.noun) or State.noun[word]
            if sub_noun then
                State.noun = sub_noun

                local index = State.current_list_index+1

                State.arguments[index] = {}
                State.arguments_fallback[index] = State.arguments_fallback[index] or {}

                current_list = State.arguments[index]
                current_fallback = State.arguments_fallback[index]
                State.current_list_index = index
                goto continue
            end
            if State.noun[Words[_+1]] and (Language.prepositions[word] or Language.pronouns[word]) then
                goto continue
            end
        end

        if State.verb[Words[_+1]] and (Language.prepositions[word] or Language.pronouns[word]) then
            goto continue
        end

        current_list[#current_list+1] = word
        current_fallback[#current_fallback+1] = word
        ::continue::
    end
    ::skip_input::
end

if has_input == false and interactive == false then
    Print_usage()
end

print()

if interactive then
    arg = {io.read("l")}
    goto process
end
