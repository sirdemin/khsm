# (c) goodprogrammer.ru

require 'rails_helper'
require 'support/my_spec_helper'
RSpec.describe GamesController, type: :controller do
  # обычный пользователь
  let(:user) { FactoryGirl.create(:user) }
  # админ
  let(:admin) { FactoryGirl.create(:user, is_admin: true) }
  # игра с прописанными игровыми вопросами
  let(:game_w_questions) { FactoryGirl.create(:game_with_questions, user: user) }

  # группа тестов для незалогиненного юзера (Анонимус)
  context 'Anon' do
    # из экшена show анона посылаем
    it 'should kick from #show' do
      # вызываем экшен
      get :show, id: game_w_questions.id

      # проверяем ответ
      expect(response.status).not_to eq(200) # статус не 200 ОК
      expect(response).to redirect_to(new_user_session_path) # devise должен отправить на логин
      expect(flash[:alert]).to be_truthy
    end

    it 'should kick from #create' do
      post :create, id: game_w_questions.id

      expect(response.status).not_to eq(200)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to be_truthy
    end

    it 'should kick from #answer' do
      put :answer, id: game_w_questions.id

      expect(response.status).not_to eq(200)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to be_truthy
    end

    it 'should kick from #take_money' do
      put :take_money, id: game_w_questions.id

      expect(response.status).not_to eq(200)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to be_truthy
    end
  end

  # группа тестов на экшены контроллера, доступных залогиненным юзерам
  context 'Usual user' do
    # перед каждым тестом в группе
    before(:each) { sign_in user } # логиним юзера user с помощью спец. Devise метода sign_in

    # юзер может создать новую игру
    it 'creates game' do
      # сперва накидаем вопросов, из чего собирать новую игру
      generate_questions(15)

      post :create
      game = assigns(:game) # вытаскиваем из контроллера поле @game

      # проверяем состояние этой игры
      expect(game.finished?).to be_falsey
      expect(game.user).to eq(user)
      # и редирект на страницу этой игры
      expect(response).to redirect_to(game_path(game))
      expect(flash[:notice]).to be
    end

    # юзер видит свою игру
    it '#show game' do
      get :show, id: game_w_questions.id
      game = assigns(:game) # вытаскиваем из контроллера поле @game
      expect(game.finished?).to be_falsey
      expect(game.user).to eq(user)

      expect(response.status).to eq(200) # должен быть ответ HTTP 200
      expect(response).to render_template('show') # и отрендерить шаблон show
    end

    # юзер отвечает на игру корректно - игра продолжается
    it 'answers correct' do
      # передаем параметр params[:letter]
      put :answer, id: game_w_questions.id, letter: game_w_questions.current_game_question.correct_answer_key
      game = assigns(:game)

      expect(game.finished?).to be_falsey
      expect(game.current_level).to be > 0
      expect(response).to redirect_to(game_path(game))
      expect(flash.empty?).to be_truthy # удачный ответ не заполняет flash
    end

    # тест на отработку "помощи зала"
    it 'uses audience help' do
      # сперва проверяем что в подсказках текущего вопроса пусто
      expect(game_w_questions.current_game_question.help_hash[:audience_help]).not_to be
      expect(game_w_questions.audience_help_used).to be_falsey

      # фигачим запрос в контроллен с нужным типом
      put :help, id: game_w_questions.id, help_type: :audience_help
      game = assigns(:game)

      # проверяем, что игра не закончилась, что флажок установился, и подсказка записалась
      expect(game.finished?).to be_falsey
      expect(game.audience_help_used).to be_truthy
      expect(game.current_game_question.help_hash[:audience_help]).to be
      expect(game.current_game_question.help_hash[:audience_help].keys).to contain_exactly('a', 'b', 'c', 'd')
      expect(response).to redirect_to(game_path(game))
    end

    it 'should not be able to view someone game' do
      alien_game = FactoryGirl.create(:game_with_questions)

      get :show, id: alien_game.id

      expect(response.status).not_to eq(200)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to be_truthy
    end
  end

  describe 'User takes money' do
    context 'when anon user' do
      it 'should redirect to sign in page' do
        put :take_money, id: game_w_questions.id
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when auth user' do
      it 'should not give user any money' do
        sign_in user
        put :take_money, id: game_w_questions.id

        expect(response).to redirect_to(user_path(user))
        expect(flash[:warning]).to be_truthy
      end

      it 'should give user fire proof prize' do
        sign_in user
        game_w_questions.update_attribute(:current_level, 2)

        put :take_money, id: game_w_questions.id
        game = assigns(:game)
        expect(game.finished?).to be_truthy
        expect(game.prize).to eq(200)
        user.reload
        expect(user.balance).to eq(200)
        expect(response).to redirect_to(user_path(user))
        expect(flash[:warning]).to be_truthy
      end
    end
  end

  describe 'User play game' do
    before(:each) { sign_in user }

    context 'starts second game while playing first' do
      it 'should redirect user to game in progress' do
        expect(game_w_questions.finished?).to eq(false)

        expect { post :create }.to change(Game, :count).by(0)

        game = assigns(:game)
        expect(game).to be_nil

        expect(response).to redirect_to(game_path(game_w_questions))
        expect(flash[:alert]).to be_truthy
      end
    end

    context 'when wrong answer' do
      it 'should return false and game finished' do
        put :answer, id: game_w_questions.id, letter: 'a'

        game = assigns(:game)
        answer_is_correct = assigns(:answer_is_correct)

        expect(answer_is_correct).to eq(false)
        expect(game.finished?).to eq(true)
        expect(game.status).to eq(:fail)
        expect(flash[:alert]).to be_truthy
        expect(response).to redirect_to(user_path(user))
      end
    end
  end

  describe 'User uses help' do
    before(:each) { sign_in user }

    context 'when fifty fifty help' do
      it 'should return give 2 variants and redirect' do
        expect(game_w_questions.fifty_fifty_used).to eq(false)

        put :help, id: game_w_questions.id, help_type: 'fifty_fifty'
        game = assigns(:game)

        expect(flash[:info]).to be_truthy
        expect(response).to redirect_to(game_path(game))
        expect(game.finished?).to eq(false)
        expect(game.fifty_fifty_used).to eq(true)

        question = game.current_game_question
        expect(question.help_hash[:fifty_fifty]).to be_truthy
        expect(question.help_hash[:fifty_fifty].size).to eq(2)
      end
    end

    context 'when fifty fifty help twice' do
      it 'should redirect with alert message' do
        expect(game_w_questions.fifty_fifty_used).to eq(false)

        put :help, id: game_w_questions.id, help_type: 'fifty_fifty'
        game = assigns(:game)

        expect(flash[:info]).to be_truthy
        expect(flash[:alert]).to be_falsey
        expect(game.finished?).to eq(false)
        expect(game.fifty_fifty_used).to eq(true)
        expect(response).to redirect_to(game_path(game_w_questions))

        put :help, id: game.id, help_type: 'fifty_fifty'
        game_second_time = assigns(:game)

        expect(flash[:alert]).to be_truthy
        expect(flash[:info]).to be_truthy
        expect(game_second_time.finished?).to eq(false)
        expect(game_second_time.fifty_fifty_used).to eq(true)
        expect(response).to redirect_to(game_path(game_second_time))
      end
    end

    context 'when unknown help' do
      it 'should alert' do
        expect(game_w_questions.fifty_fifty_used).to eq(false)
        expect(game_w_questions.audience_help_used).to eq(false)
        expect(game_w_questions.friend_call_used).to eq(false)

        put :help, id: game_w_questions.id, help_type: 'something'
        game = assigns(:game)


        expect(game.fifty_fifty_used).to eq(false)
        expect(game.audience_help_used).to eq(false)
        expect(game.friend_call_used).to eq(false)

        expect(flash[:alert]).to be_truthy
        expect(game.finished?).to eq(false)
        expect(response).to redirect_to(game_path(game))
      end
    end
  end
end
