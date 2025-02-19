Pod::Spec.new do |s|

s.platform = :ios
s.ios.deployment_target = '11.0'
s.name = "NeuroID"
s.summary = "A Swift implementation of a custom UIControl for selecting a range of values on a slider bar."
s.requires_arc = true
s.swift_version = '5.0'

s.version = "0.0.1"
s.license = { :type => "MIT", :text => <<-LICENSE
Copyright (c) 2021 Neuro-ID <product@neuro-id.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

LICENSE
 }
s.author = { "Neuro-ID" => "Neuro-ID" }
s.homepage = "https://neuro-id.com/"
s.source = { :git => "https://github.com/Neuro-ID/neuroid-ios-sdk.git", :tag => "#{s.version}"}

s.source_files = "NeuroID/**/*.{h,c,m,swift,mlmodel,mlmodelc}"
end