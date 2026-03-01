# tests/Parser.Tests.ps1
Describe "Tool Call Parser" {
    BeforeAll {
        function Parse-ToolCall {
            param([string]$modelText)
            
            $jsonStr = $null
            if ($modelText -match '(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>') {
                $jsonStr = $matches[1]
            }
            elseif ($modelText -match '(?s)```tool_code\s*(\{.*?\})\s*```') {
                $jsonStr = $matches[1]
            }
            elseif ($modelText -match '(?s)```json\s*(\{.*?""name"".*?\})\s*```') {
                $jsonStr = $matches[1]
            }
            elseif ($modelText -match '(?s)(\w+)\(\s*(\{.*?\})\s*\)') {
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
        $modelText = '```tool_code`n{""name"": ""searchdir"",""parameters"":{""dir_path"": ""."",""search_string"": ""*""}}`n```'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }

    It "should parse json style tool calls" {
        $modelText = '```json`n{""name"": ""searchdir"",""parameters"":{""dir_path"": ""."",""search_string"": ""*""}}`n```'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }

    It "should parse bare function style tool calls" {
        $modelText = 'searchdir({""dir_path"": ""."",""search_string"": ""*""})'
        $result = Parse-ToolCall -modelText $modelText
        $result | Should Not BeNullOrEmpty
    }
}
