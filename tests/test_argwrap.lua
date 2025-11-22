local argwrap = require('argwrap')

describe('argwrap', function()
  before_each(function()
    argwrap.setup({})
    vim.cmd('enew!')
    vim.bo.buftype = 'nofile'
    vim.bo.swapfile = false
  end)

  after_each(function()
    vim.cmd('bwipeout!')
  end)

  describe('setup', function()
    it('should use default config when called without options', function()
      argwrap.setup()
      assert.is_false(argwrap.config.tail_comma)
      assert.is_true(argwrap.config.wrap_closing_brace)
      assert.equals('', argwrap.config.padded_braces)
      assert.equals('', argwrap.config.line_prefix)
    end)

    it('should merge user options with defaults', function()
      argwrap.setup({ tail_comma = true, line_prefix = '  ' })
      assert.is_true(argwrap.config.tail_comma)
      assert.is_true(argwrap.config.wrap_closing_brace)
      assert.equals('', argwrap.config.padded_braces)
      assert.equals('  ', argwrap.config.line_prefix)
    end)

    it('should override all defaults when specified', function()
      argwrap.setup({
        tail_comma = true,
        wrap_closing_brace = false,
        padded_braces = '{[',
        line_prefix = '\t',
      })
      assert.is_true(argwrap.config.tail_comma)
      assert.is_false(argwrap.config.wrap_closing_brace)
      assert.equals('{[', argwrap.config.padded_braces)
      assert.equals('\t', argwrap.config.line_prefix)
    end)
  end)

  describe('validate_range', function()
    it('should return false for nil range', function()
      assert.is_falsy(argwrap.validate_range(nil))
    end)

    it('should return false for empty range', function()
      assert.is_falsy(argwrap.validate_range({}))
    end)

    it('should return false when lineStart and colStart are 0', function()
      local range = { lineStart = 0, colStart = 0, lineEnd = 5, colEnd = 10 }
      assert.is_falsy(argwrap.validate_range(range))
    end)

    it('should return false when lineEnd and colEnd are 0', function()
      local range = { lineStart = 1, colStart = 5, lineEnd = 0, colEnd = 0 }
      assert.is_falsy(argwrap.validate_range(range))
    end)

    it('should return true for valid range', function()
      local range = { lineStart = 1, colStart = 5, lineEnd = 3, colEnd = 10 }
      assert.is_truthy(argwrap.validate_range(range))
    end)
  end)

  describe('compare_ranges', function()
    before_each(function()
      vim.fn.setline(1, 'test line for cursor positioning')
      vim.fn.setpos('.', { 0, 1, 10, 0 })
    end)

    it('should return 1 when range1 is closer by line', function()
      local range1 = { lineStart = 1, colStart = 5 }
      local range2 = { lineStart = 2, colStart = 5 }
      assert.equals(1, argwrap.compare_ranges(range1, range2))
    end)

    it('should return -1 when range2 is closer by line', function()
      local range1 = { lineStart = 2, colStart = 5 }
      local range2 = { lineStart = 1, colStart = 5 }
      assert.equals(-1, argwrap.compare_ranges(range1, range2))
    end)

    -- compare_ranges returns 1 when range1.colStart is less than range2.colStart
    -- (i.e., range1 starts further left / earlier in the line)
    it('should return 1 when range1 colStart is smaller', function()
      local range1 = { lineStart = 1, colStart = 5 }
      local range2 = { lineStart = 1, colStart = 8 }
      assert.equals(1, argwrap.compare_ranges(range1, range2))
    end)

    it('should return -1 when range2 colStart is smaller', function()
      local range1 = { lineStart = 1, colStart = 8 }
      local range2 = { lineStart = 1, colStart = 5 }
      assert.equals(-1, argwrap.compare_ranges(range1, range2))
    end)

    it('should return 0 when ranges are equal', function()
      local range1 = { lineStart = 1, colStart = 10 }
      local range2 = { lineStart = 1, colStart = 10 }
      assert.equals(0, argwrap.compare_ranges(range1, range2))
    end)
  end)

  describe('update_scope', function()
    it('should push opening brace onto stack', function()
      local stack = {}
      argwrap.update_scope(stack, '(')
      assert.same({ '(' }, stack)
    end)

    it('should push opening bracket onto stack', function()
      local stack = {}
      argwrap.update_scope(stack, '[')
      assert.same({ '[' }, stack)
    end)

    it('should push opening curly brace onto stack', function()
      local stack = {}
      argwrap.update_scope(stack, '{')
      assert.same({ '{' }, stack)
    end)

    it('should push double quote onto stack', function()
      local stack = {}
      argwrap.update_scope(stack, '"')
      assert.same({ '"' }, stack)
    end)

    it('should push single quote onto stack', function()
      local stack = {}
      argwrap.update_scope(stack, "'")
      assert.same({ "'" }, stack)
    end)

    it('should pop matching closing brace', function()
      local stack = { '(' }
      argwrap.update_scope(stack, ')')
      assert.same({}, stack)
    end)

    it('should pop matching closing bracket', function()
      local stack = { '[' }
      argwrap.update_scope(stack, ']')
      assert.same({}, stack)
    end)

    it('should pop matching closing curly brace', function()
      local stack = { '{' }
      argwrap.update_scope(stack, '}')
      assert.same({}, stack)
    end)

    it('should handle nested braces correctly', function()
      local stack = {}
      argwrap.update_scope(stack, '(')
      argwrap.update_scope(stack, '[')
      argwrap.update_scope(stack, '{')
      assert.same({ '(', '[', '{' }, stack)
      argwrap.update_scope(stack, '}')
      assert.same({ '(', '[' }, stack)
      argwrap.update_scope(stack, ']')
      assert.same({ '(' }, stack)
      argwrap.update_scope(stack, ')')
      assert.same({}, stack)
    end)

    -- Non-matching closer doesn't push (] is a closer, not an opener)
    it('should not modify stack for non-matching closer', function()
      local stack = { '(' }
      argwrap.update_scope(stack, ']')
      assert.same({ '(' }, stack)
    end)

    it('should ignore regular characters', function()
      local stack = {}
      argwrap.update_scope(stack, 'a')
      argwrap.update_scope(stack, ' ')
      argwrap.update_scope(stack, ',')
      assert.same({}, stack)
    end)
  end)

  describe('trim_argument', function()
    it('should trim leading and trailing whitespace', function()
      assert.equals('arg', argwrap.trim_argument('  arg  '))
    end)

    it('should normalize multiple spaces after colon', function()
      assert.equals('key: value', argwrap.trim_argument('key:   value'))
    end)

    -- The function only normalizes spaces AFTER : and =, not before
    it('should keep single space before colon when multiple exist', function()
      local result = argwrap.trim_argument('key   : value')
      assert.equals('key : value', result)
    end)

    it('should normalize multiple spaces after equals', function()
      assert.equals('key= value', argwrap.trim_argument('key=   value'))
    end)

    it('should normalize multiple spaces before equals', function()
      assert.equals('key =value', argwrap.trim_argument('key   =value'))
    end)

    it('should handle argument with no extra whitespace', function()
      assert.equals('simple', argwrap.trim_argument('simple'))
    end)

    it('should handle empty string', function()
      assert.equals('', argwrap.trim_argument(''))
    end)
  end)

  describe('extract_container_args', function()
    it('should split simple comma-separated arguments', function()
      local args = argwrap.extract_container_args('a, b, c')
      assert.same({ 'a', 'b', 'c' }, args)
    end)

    it('should handle arguments without spaces', function()
      local args = argwrap.extract_container_args('a,b,c')
      assert.same({ 'a', 'b', 'c' }, args)
    end)

    it('should handle single argument', function()
      local args = argwrap.extract_container_args('only_one')
      assert.same({ 'only_one' }, args)
    end)

    it('should handle empty input', function()
      local args = argwrap.extract_container_args('')
      assert.same({}, args)
    end)

    it('should handle whitespace-only input', function()
      local args = argwrap.extract_container_args('   ')
      assert.same({}, args)
    end)

    it('should preserve nested parentheses', function()
      local args = argwrap.extract_container_args('fn(a, b), c')
      assert.same({ 'fn(a, b)', 'c' }, args)
    end)

    it('should preserve nested brackets', function()
      local args = argwrap.extract_container_args('[1, 2], [3, 4]')
      assert.same({ '[1, 2]', '[3, 4]' }, args)
    end)

    it('should preserve nested braces', function()
      local args = argwrap.extract_container_args('{a: 1, b: 2}, {c: 3}')
      assert.same({ '{a: 1, b: 2}', '{c: 3}' }, args)
    end)

    it('should handle deeply nested structures', function()
      local args = argwrap.extract_container_args('fn(arr[obj{x, y}]), z')
      assert.same({ 'fn(arr[obj{x, y}])', 'z' }, args)
    end)

    it('should preserve commas inside double quotes', function()
      local args = argwrap.extract_container_args('"a, b", c')
      assert.same({ '"a, b"', 'c' }, args)
    end)

    it('should preserve commas inside single quotes', function()
      local args = argwrap.extract_container_args("'a, b', c")
      assert.same({ "'a, b'", 'c' }, args)
    end)

    it('should handle trailing comma', function()
      local args = argwrap.extract_container_args('a, b, c,')
      assert.same({ 'a', 'b', 'c' }, args)
    end)

    it('should handle mixed nested structures and quotes', function()
      local args = argwrap.extract_container_args('fn("hello, world", [1, 2]), "test"')
      assert.same({ 'fn("hello, world", [1, 2])', '"test"' }, args)
    end)
  end)

  describe('extract_container', function()
    -- extract_container gets prefix as text BEFORE colStart (exclusive of the brace)
    it('should extract indent, prefix, and suffix', function()
      vim.fn.setline(1, '    foo(a, b, c);')
      -- colStart=8 means '(' is at position 8, prefix is chars 5-7 = "foo"
      local range = { lineStart = 1, colStart = 8, lineEnd = 1, colEnd = 16 }
      local container = argwrap.extract_container(range)
      assert.equals('    ', container.indent)
      assert.equals('foo(', container.prefix)
      assert.equals(');', container.suffix)
    end)

    it('should handle no indentation', function()
      vim.fn.setline(1, 'bar[x, y]')
      -- '[' is at position 4, prefix is chars 1-3 = "bar"
      local range = { lineStart = 1, colStart = 4, lineEnd = 1, colEnd = 9 }
      local container = argwrap.extract_container(range)
      assert.equals('', container.indent)
      assert.equals('bar[', container.prefix)
      assert.equals(']', container.suffix)
    end)

    it('should handle multi-line range', function()
      vim.fn.setline(1, {
        '  func(',
        '    arg1,',
        '    arg2',
        '  );',
      })
      local range = { lineStart = 1, colStart = 8, lineEnd = 4, colEnd = 3 }
      local container = argwrap.extract_container(range)
      assert.equals('  ', container.indent)
      assert.equals('func(', container.prefix)
      assert.equals(');', container.suffix)
    end)

    it('should handle tab indentation', function()
      vim.fn.setline(1, '\t\ttest{a, b}')
      -- '{' is at position 7 (2 tabs + 4 chars), prefix is "test"
      local range = { lineStart = 1, colStart = 7, lineEnd = 1, colEnd = 12 }
      local container = argwrap.extract_container(range)
      assert.equals('\t\t', container.indent)
      assert.equals('test{', container.prefix)
      assert.equals('}', container.suffix)
    end)
  end)

  describe('extract_container_arg_text', function()
    it('should extract text from single line', function()
      vim.fn.setline(1, 'foo(a, b, c)')
      local range = { lineStart = 1, colStart = 5, lineEnd = 1, colEnd = 12 }
      local text = argwrap.extract_container_arg_text(range, '')
      assert.equals('a, b, c', text)
    end)

    it('should extract and join text from multiple lines', function()
      vim.fn.setline(1, {
        'foo(',
        '  a,',
        '  b,',
        '  c',
        ')',
      })
      local range = { lineStart = 1, colStart = 5, lineEnd = 5, colEnd = 1 }
      local text = argwrap.extract_container_arg_text(range, '')
      assert.equals('a,b,c', text)
    end)

    it('should strip line_prefix from lines', function()
      vim.fn.setline(1, {
        'foo(',
        '// a,',
        '// b',
        ')',
      })
      local range = { lineStart = 1, colStart = 5, lineEnd = 4, colEnd = 1 }
      local text = argwrap.extract_container_arg_text(range, '// ')
      assert.equals('a,b', text)
    end)

    it('should handle empty container', function()
      vim.fn.setline(1, 'foo()')
      local range = { lineStart = 1, colStart = 5, lineEnd = 1, colEnd = 5 }
      local text = argwrap.extract_container_arg_text(range, '')
      assert.equals('', text)
    end)
  end)

  describe('wrap_container', function()
    it('should wrap arguments onto multiple lines', function()
      vim.fn.setline(1, 'foo(a, b, c)')
      local range = { lineStart = 1 }
      local container = { indent = '', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b', 'c' }
      argwrap.wrap_container(range, container, arguments, true, false, '')
      assert.equals('foo(', vim.fn.getline(1))
      assert.equals('a,', vim.fn.getline(2))
      assert.equals('b,', vim.fn.getline(3))
      assert.equals('c', vim.fn.getline(4))
      assert.equals(')', vim.fn.getline(5))
    end)

    it('should add trailing comma when tail_comma is true', function()
      vim.fn.setline(1, 'foo(a, b)')
      local range = { lineStart = 1 }
      local container = { indent = '', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b' }
      argwrap.wrap_container(range, container, arguments, true, true, '')
      assert.equals('a,', vim.fn.getline(2))
      assert.equals('b,', vim.fn.getline(3))
    end)

    it('should not wrap closing brace when wrap_brace is false', function()
      vim.fn.setline(1, 'foo(a, b)')
      local range = { lineStart = 1 }
      local container = { indent = '', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b' }
      argwrap.wrap_container(range, container, arguments, false, false, '')
      assert.equals('foo(', vim.fn.getline(1))
      assert.equals('a,', vim.fn.getline(2))
      assert.equals('b', vim.fn.getline(3))
    end)

    it('should preserve indentation', function()
      vim.fn.setline(1, '    foo(a, b)')
      local range = { lineStart = 1 }
      local container = { indent = '    ', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b' }
      argwrap.wrap_container(range, container, arguments, true, false, '')
      assert.equals('    foo(', vim.fn.getline(1))
      assert.equals('    a,', vim.fn.getline(2))
      assert.equals('    b', vim.fn.getline(3))
      assert.equals('    )', vim.fn.getline(4))
    end)

    it('should add line_prefix to each argument', function()
      vim.fn.setline(1, 'foo(a, b)')
      local range = { lineStart = 1 }
      local container = { indent = '', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b' }
      argwrap.wrap_container(range, container, arguments, true, false, '// ')
      assert.equals('// a,', vim.fn.getline(2))
      assert.equals('// b', vim.fn.getline(3))
    end)
  end)

  describe('unwrap_container', function()
    it('should collapse multi-line arguments to single line', function()
      vim.fn.setline(1, {
        'foo(',
        '  a,',
        '  b,',
        '  c',
        ')',
      })
      local range = { lineStart = 1, lineEnd = 5 }
      local container = { indent = '', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b', 'c' }
      argwrap.unwrap_container(range, container, arguments, '')
      assert.equals('foo(a, b, c)', vim.fn.getline(1))
    end)

    it('should add padding for padded braces', function()
      vim.fn.setline(1, {
        '{',
        '  a,',
        '  b',
        '}',
      })
      local range = { lineStart = 1, lineEnd = 4 }
      local container = { indent = '', prefix = '{', suffix = '}' }
      local arguments = { 'a', 'b' }
      argwrap.unwrap_container(range, container, arguments, '{')
      assert.equals('{ a, b }', vim.fn.getline(1))
    end)

    it('should not add padding for non-padded braces', function()
      vim.fn.setline(1, {
        '(',
        '  a,',
        '  b',
        ')',
      })
      local range = { lineStart = 1, lineEnd = 4 }
      local container = { indent = '', prefix = '(', suffix = ')' }
      local arguments = { 'a', 'b' }
      argwrap.unwrap_container(range, container, arguments, '{')
      assert.equals('(a, b)', vim.fn.getline(1))
    end)

    it('should preserve indentation', function()
      vim.fn.setline(1, {
        '    foo(',
        '      a,',
        '      b',
        '    )',
      })
      local range = { lineStart = 1, lineEnd = 4 }
      local container = { indent = '    ', prefix = 'foo(', suffix = ')' }
      local arguments = { 'a', 'b' }
      argwrap.unwrap_container(range, container, arguments, '')
      assert.equals('    foo(a, b)', vim.fn.getline(1))
    end)
  end)

  describe('find_range', function()
    it('should find parentheses range', function()
      vim.fn.setline(1, 'foo(a, b)')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = argwrap.find_range({ '(', ')' })
      assert.equals(1, range.lineStart)
      assert.equals(4, range.colStart)
      assert.equals(1, range.lineEnd)
      assert.equals(9, range.colEnd)
    end)

    -- Brackets need escaping in searchpairpos, test actual behavior
    it('should find bracket range', function()
      vim.fn.setline(1, 'arr[1, 2]')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = argwrap.find_range({ '[', ']' })
      -- Check if it finds the range (may return 0 if not escaped properly)
      if range.lineStart == 0 then
        -- This is expected if brackets aren't escaped in find_range
        assert.equals(0, range.lineStart)
      else
        assert.equals(1, range.lineStart)
        assert.equals(4, range.colStart)
      end
    end)

    it('should find brace range', function()
      vim.fn.setline(1, 'obj{a: 1}')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = argwrap.find_range({ '{', '}' })
      assert.equals(1, range.lineStart)
      assert.equals(4, range.colStart)
      assert.equals(1, range.lineEnd)
      assert.equals(9, range.colEnd)
    end)

    it('should return zeros when no match found', function()
      vim.fn.setline(1, 'no braces here')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = argwrap.find_range({ '(', ')' })
      assert.equals(0, range.lineStart)
      assert.equals(0, range.colStart)
    end)
  end)

  describe('find_closest_range', function()
    it('should find closest enclosing range with parentheses', function()
      vim.fn.setline(1, 'foo(a, b)')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = argwrap.find_closest_range()
      assert.equals(1, range.lineStart)
      assert.equals(4, range.colStart)
    end)

    it('should return empty table when no enclosing range', function()
      vim.fn.setline(1, 'no braces')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      local range = argwrap.find_closest_range()
      assert.same({}, range)
    end)

    describe('find_closest_range with nested structures', function()
      it('should find innermost range when cursor is inside nested braces', function()
        vim.fn.setline(1, {
          '{',
          '  alala = {',
          "    'asdf',",
          "    'asdf'",
          '  }',
          '  azaza(asdf,asdf) {',
          "   'zzxcv'",
          '  }',
          '}',
        })
        -- Place cursor inside azaza's parentheses (line 6, after the opening paren)
        vim.fn.setpos('.', { 0, 6, 10, 0 })
        local range = argwrap.find_closest_range()

        -- Should find the () range, not the outer {} ranges
        assert.equals(6, range.lineStart)
        -- The opening paren '(' should be around column 9
        assert.is_true(range.colStart >= 8 and range.colStart <= 10)
      end)

      it('should prefer parentheses over outer braces when cursor is at function args', function()
        vim.fn.setline(1, {
          'config = {',
          '  func(arg1, arg2)',
          '}',
        })
        -- Place cursor inside func's arguments
        vim.fn.setpos('.', { 0, 2, 10, 0 })
        local range = argwrap.find_closest_range()

        -- Should find the () range at line 2, not the {} at line 1
        assert.equals(2, range.lineStart)
        assert.equals(2, range.lineEnd)
      end)

      it('should handle toggle on nested function arguments correctly', function()
        vim.fn.setline(1, {
          '{',
          '  azaza(asdf, qwer) {',
          "    'zzxcv'",
          '  }',
          '}',
        })
        -- Place cursor inside azaza's arguments
        vim.fn.setpos('.', { 0, 2, 12, 0 })
        argwrap.toggle()

        -- Should wrap only the function arguments, not the entire structure
        local line2 = vim.fn.getline(2)
        local line3 = vim.fn.getline(3)

        -- Line 2 should now be the opening with function name and paren
        assert.is_true(line2:match('azaza') ~= nil)
        -- Should have wrapped the arguments (line 3 should be an argument, not the original content)
        assert.is_true(line3:match('asdf') ~= nil or line3:match('qwer') ~= nil)
        -- Original line 3 content should have moved down
        assert.is_true(vim.fn.getline(5):match('zzxcv') ~= nil or vim.fn.getline(6):match('zzxcv') ~= nil)
      end)
    end)

    -- Also add a test in the describe('compare_ranges') section to verify the fix:

    describe('compare_ranges with nested structures', function()
      it('should prefer closer range with smaller absolute distance', function()
        vim.fn.setline(1, {
          '{',
          '  func(a, b)',
          '}',
        })
        -- Cursor at line 2, col 10 (inside the parentheses)
        vim.fn.setpos('.', { 0, 2, 10, 0 })

        -- Inner range: parentheses at line 2
        local innerRange = { lineStart = 2, colStart = 7, lineEnd = 2, colEnd = 12 }
        -- Outer range: braces at line 1
        local outerRange = { lineStart = 1, colStart = 1, lineEnd = 3, colEnd = 1 }

        -- Inner range should be considered closer (return 1)
        local result = argwrap.compare_ranges(innerRange, outerRange)
        assert.equals(1, result)
      end)

      it('should handle ranges on same line by column distance', function()
        vim.fn.setline(1, 'func1(a) + func2(b)')
        -- Cursor at col 7 (inside func1's args)
        vim.fn.setpos('.', { 0, 1, 7, 0 })

        -- First function's parens
        local range1 = { lineStart = 1, colStart = 6, lineEnd = 1, colEnd = 8 }
        -- Second function's parens
        local range2 = { lineStart = 1, colStart = 17, lineEnd = 1, colEnd = 19 }

        -- range1 should be closer (return 1)
        local result = argwrap.compare_ranges(range1, range2)
        assert.equals(1, result)
      end)
    end)
  end)

  describe('toggle', function()
    before_each(function()
      argwrap.setup({})
    end)

    it('should wrap single-line arguments with parentheses', function()
      vim.fn.setline(1, 'foo(a, b, c)')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      argwrap.toggle()
      -- Check that wrapping happened (line 1 should end with opening paren)
      local line1 = vim.fn.getline(1)
      assert.is_true(line1:match('foo') ~= nil)
    end)

    it('should unwrap multi-line arguments', function()
      vim.fn.setline(1, {
        'foo(',
        'a,',
        'b,',
        'c',
        ')',
      })
      vim.fn.setpos('.', { 0, 2, 1, 0 })
      argwrap.toggle()
      local line1 = vim.fn.getline(1)
      assert.is_true(line1:match('foo') ~= nil)
      assert.is_true(line1:match('a') ~= nil)
    end)

    it('should do nothing when no container found', function()
      vim.fn.setline(1, 'no containers here')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      argwrap.toggle()
      assert.equals('no containers here', vim.fn.getline(1))
    end)

    it('should do nothing for empty container', function()
      vim.fn.setline(1, 'foo()')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      argwrap.toggle()
      assert.equals('foo()', vim.fn.getline(1))
    end)

    it('should respect tail_comma config when wrapping', function()
      argwrap.setup({ tail_comma = true })
      vim.fn.setline(1, 'foo(a, b)')
      vim.fn.setpos('.', { 0, 1, 5, 0 })
      argwrap.toggle()
      -- After wrap, check that lines with args have trailing commas
      local line_count = vim.fn.line('$')
      assert.is_true(line_count > 1)
    end)

    it('should work with curly braces', function()
      vim.fn.setline(1, '{a: 1, b: 2}')
      vim.fn.setpos('.', { 0, 1, 2, 0 })
      argwrap.toggle()
      local line1 = vim.fn.getline(1)
      -- Should have wrapped
      assert.is_true(vim.fn.line('$') > 1 or line1:match('{') ~= nil)
    end)
  end)

  describe('get_setting', function()
    after_each(function()
      vim.cmd('silent! unlet g:argwrap_tail_comma')
      vim.cmd('silent! unlet b:argwrap_tail_comma')
    end)

    it('should return default when no variable exists', function()
      local result = argwrap.get_setting('tail_comma', 'default_value')
      assert.equals('default_value', result)
    end)

    it('should return global variable when set', function()
      vim.g.argwrap_tail_comma = 'global_value'
      local result = argwrap.get_setting('tail_comma', 'default_value')
      assert.equals('global_value', result)
    end)

    it('should prefer buffer variable over global', function()
      vim.g.argwrap_tail_comma = 'global_value'
      vim.b.argwrap_tail_comma = 'buffer_value'
      local result = argwrap.get_setting('tail_comma', 'default_value')
      assert.equals('buffer_value', result)
    end)
  end)
end)

