# frozen_string_literal: true

# Copyright (c) 2017-present, BigCommerce Pty. Ltd. All rights reserved
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
# Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
require 'spec_helper'

describe Gruf::Server do
  subject { gruf_server }

  let(:options) { {} }
  let(:gruf_server) { described_class.new(options) }

  shared_context 'with stop thread mocked' do
    let(:thread_mock) { double(Thread, join: nil) }

    before do
      allow(Thread).to receive(:new) { thread_mock }
    end
  end

  describe '#start!' do
    let(:server_mock) { double(GRPC::RpcServer, add_http2_port: nil, run: nil, wait_till_running: nil) }

    context 'when valid options passed' do
      include_context 'with stop thread mocked'

      let(:options) { { pool_size: Random.rand(10) } }

      it 'runs server with given overrides' do
        expect(GRPC::RpcServer).to receive(:new)
          .with(Gruf.rpc_server_options.merge(options)).and_return(server_mock)
        gruf_server.start!
      end
    end

    context 'when invalid options passed' do
      include_context 'with stop thread mocked'

      let(:options) { { random_option: Random.rand(10) } }

      it 'runs server with default configuration' do
        expect(GRPC::RpcServer).to receive(:new)
          .with(Gruf.rpc_server_options).and_return(server_mock)
        gruf_server.start!
      end
    end

    context 'when some valid and some invalid options passed' do
      include_context 'with stop thread mocked'

      let(:options) { { random_option: Random.rand(10), pool_size: Random.rand(10) } }

      it 'runs server with valid overrides only' do
        valid_options = { pool_size: options[:pool_size] }
        expect(GRPC::RpcServer).to receive(:new)
          .with(Gruf.rpc_server_options.merge(valid_options)).and_return(server_mock)
        gruf_server.start!
      end
    end

    context 'when no options passed' do
      include_context 'with stop thread mocked'

      it 'runs server with default configuration' do
        expect(GRPC::RpcServer).to receive(:new)
          .with(Gruf.rpc_server_options).and_return(server_mock)
        gruf_server.start!
      end
    end

    context 'when TERM signal is received' do
      it 'stops gracefully' do
        server_thread = Thread.new do
          srv = described_class.new
          srv.server.handle(::Rpc::ThingService::Service)
          srv.start!
        end
        sleep 3 # wait for a server to boot up
        Process.kill('TERM', Process.pid)
        server_thread.join
        expect(server_thread.status).to be false # expect thread to exit normally
      end
    end
  end

  describe '#add_service' do
    subject { gruf_server.add_service(service) }

    let(:service) { Rpc::ThingService }

    context 'when the service is not yet in the registry' do
      it 'adds a service to the registry' do
        expect { subject }.to(change { gruf_server.instance_variable_get('@services').count }.by(1))
        expect(gruf_server.instance_variable_get('@services')).to eq [service]
      end
    end

    context 'when the service is already in the registry' do
      it 'does not add the service' do
        gruf_server.add_service(service)
        expect { subject }.not_to(change { gruf_server.instance_variable_get('@services').count })
      end
    end

    context 'when the server is already started' do
      before do
        gruf_server.instance_variable_set(:@started, true)
      end

      it 'raises a ServerAlreadyStartedError exception' do
        expect { subject }.to raise_error(Gruf::Server::ServerAlreadyStartedError)
      end
    end
  end

  describe '#add_interceptor' do
    subject { gruf_server.add_interceptor(interceptor_class, interceptor_options) }

    let(:interceptor_class) { TestServerInterceptor }
    let(:interceptor_options) { { foo: 'bar' } }

    before do
      Gruf.interceptors.clear
    end

    it 'adds the interceptor to the registry' do
      expect { subject }.to(change { gruf_server.instance_variable_get('@interceptors').count }.by(1))
      is = gruf_server.instance_variable_get('@interceptors').prepare(nil, nil)
      i = is.first
      expect(i).to be_a(interceptor_class)
      expect(i.options).to eq interceptor_options
    end

    context 'when the server is already started' do
      before do
        gruf_server.instance_variable_set(:@started, true)
      end

      it 'raises a ServerAlreadyStartedError exception' do
        expect { subject }.to raise_error(Gruf::Server::ServerAlreadyStartedError)
      end
    end
  end

  describe '#list_interceptors' do
    subject { gruf_server.list_interceptors }

    let(:interceptor) { TestServerInterceptor }

    before do
      Gruf.interceptors.clear
      gruf_server.add_interceptor(interceptor)
    end

    it 'returns the current list of interceptors' do
      expect(subject).to eq [interceptor]
    end
  end

  describe '#insert_interceptor_before' do
    subject { gruf_server.insert_interceptor_before(interceptor, interceptor2) }

    let(:interceptor) { TestServerInterceptor }
    let(:interceptor2) { TestServerInterceptor2 }

    before do
      Gruf.interceptors.clear
      gruf_server.add_interceptor(interceptor)
    end

    it 'adds the new interceptor before the targeted one' do
      expect { subject }.not_to raise_error
      expect(gruf_server.list_interceptors).to eq [interceptor2, interceptor]
    end

    context 'when the server is already started' do
      before do
        gruf_server.instance_variable_set(:@started, true)
      end

      it 'raises a ServerAlreadyStartedError exception' do
        expect { subject }.to raise_error(Gruf::Server::ServerAlreadyStartedError)
      end
    end
  end

  describe '.insert_interceptor_after' do
    subject { gruf_server.insert_interceptor_after(interceptor, interceptor3) }

    let(:interceptor) { TestServerInterceptor }
    let(:interceptor2) { TestServerInterceptor2 }
    let(:interceptor3) { TestServerInterceptor3 }

    before do
      Gruf.interceptors.clear
      gruf_server.add_interceptor(interceptor)
      gruf_server.add_interceptor(interceptor2)
    end

    it 'adds the new interceptor after the targeted one' do
      expect { subject }.not_to raise_error
      expect(gruf_server.list_interceptors).to eq [interceptor, interceptor3, interceptor2]
    end

    context 'when the server is already started' do
      before do
        gruf_server.instance_variable_set(:@started, true)
      end

      it 'raises a ServerAlreadyStartedError exception' do
        expect { subject }.to raise_error(Gruf::Server::ServerAlreadyStartedError)
      end
    end
  end

  describe '#remove_interceptor' do
    subject { gruf_server.remove_interceptor(interceptor) }

    let(:interceptor) { TestServerInterceptor }
    let(:interceptor2) { TestServerInterceptor2 }
    let(:interceptor3) { TestServerInterceptor3 }

    before do
      Gruf.interceptors.clear
      gruf_server.add_interceptor(interceptor2)
      gruf_server.add_interceptor(interceptor3)
    end

    context 'when the interceptor is in the registry' do
      before do
        gruf_server.add_interceptor(interceptor)
      end

      it 'removes the interceptor from the registry' do
        expect { subject }.not_to raise_error
        expect(gruf_server.list_interceptors.count).to eq 2
      end
    end

    context 'when the interceptor is not in the registry' do
      it 'raises a InterceptorNotFoundError exception' do
        expect { subject }.to raise_error(Gruf::Interceptors::Registry::InterceptorNotFoundError)
      end
    end

    context 'when the server is already started' do
      before do
        gruf_server.instance_variable_set(:@started, true)
      end

      it 'raises a ServerAlreadyStartedError exception' do
        expect { subject }.to raise_error(Gruf::Server::ServerAlreadyStartedError)
      end
    end
  end

  describe '#clear_interceptors' do
    subject { gruf_server.clear_interceptors }

    let(:interceptor) { TestServerInterceptor }

    before do
      Gruf.interceptors.clear
      gruf_server.add_interceptor(interceptor)
    end

    it 'clears all interceptors from the registry' do
      expect { subject }.not_to raise_error
      expect(gruf_server.list_interceptors).to eq []
    end

    context 'when the server is already started' do
      before do
        gruf_server.instance_variable_set(:@started, true)
      end

      it 'raises a ServerAlreadyStartedError exception' do
        expect { subject }.to raise_error(Gruf::Server::ServerAlreadyStartedError)
      end
    end
  end
end
