# tests/Parser.Tests.ps1
Describe "Tool Call Parser" {
    BeforeAll {
        function Parse-ToolCall {
            param([string]$modelText)
            
            $jsonStr = $null
            # Format 1: Official XML style <tool_call>{...}</tool_call>
            if ($modelText -match '(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>' -and $modelText -notmatch '<code_block>') {
                $jsonStr = $matches[1]
            }
            # Format 2: Markdown style ```tool_code\n{...}\n```
            elseif ($modelText -match '(?s)```tool_code\s*(\{.*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```tool_code' -and $modelText -notmatch '<code_block>') {
                $jsonStr = $matches[1]
            }
            # Format 3: Codefence style ```tool_call\n{...}\n```
            elseif ($modelText -match '(?s)```tool_call\s*(\{.*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```tool_call' -and $modelText -notmatch '<code_block>') {
                $jsonStr = $matches[1]
            }
            # Format 4: Plain ```json\n{...}\n``` with a name field
            elseif ($modelText -match '(?s)```json\s*(\{.*?""name"".*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```json' -and $modelText -notmatch '<code_block>') {
                $jsonStr = $matches[1]
            }
            # Format 5: Bare function call style tool_name({"param": "value"})
            elseif ($modelText -match '(?s)(\w+)\(\s*(\{.*?\})\s*\)' -and $modelText -notmatch '<code_block>') {
                $jsonStr = "{`"name`": `"$($matches[1])`", `"parameters`": $($matches[2])}"
            }
            return $jsonStr
        }
    }

    It "should parse XML style tool calls" {
        $modelText = '<tool_call>{""name"": ""searchdir"",""parameters"":{""dir_path"": ""."",""search_string"": ""*""}}</tool_call>'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }

    It "should parse markdown style tool calls" {
        $modelText = '```tool_code' + "`n" + '{""name"": ""searchdir"",""parameters"":{""dir_path"": ""."",""search_string"": ""*""}}' + "`n" + '```'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }

    It "should parse json style tool calls" {
        $modelText = '```json' + "`n" + '{""name"": ""searchdir"",""parameters"":{""dir_path"": ""."",""search_string"": ""*""}}' + "`n" + '```'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }

    It "should parse bare function style tool calls" {
        $modelText = 'searchdir({""dir_path"": ""."",""search_string"": ""*""})'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }
}
