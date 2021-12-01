#!/bin/bash

numeroRobot=$1			#numero du robot passe en parametre dans le gestionnaire du jeu
partieFini=false		#boolean pour savoir si la partie est finie
topDepart=false			#boolean pour lancer la partie
cartesRobot=()			#les cartes que le robot possede
carteCourante=0			#la carte joué par le robot

#methode qui recupere les cartes 
waitCartes()
{	
	onAttend=true
	while [ $onAttend == "true" ]
	do
		#permet de recevoir les cartes dans l'ordre des robots
		sleep $numeroRobot
		
		#Envoie au gestionnaire du jeu que le robots a recu les cartes
		echo "Robot $numeroRobot a recu ses cartes." | nc localhost 9091 2> /dev/null | echo "Vous avez reçu vos cartes" & onAttend=false
	done
	
	#on trie le fichier qui contient les cartes
	sort -n tmp/cartePartie -o tmp/cartePartie
	
	for i in $(eval echo {1..$(wc -w tmp/cartePartie | cut -d" " -f1)}); #nombre d'élément dans le fichier
	do	
		cartesRobot+=($(echo $(cat tmp/cartePartie) | cut -d" " -f$i))	
	done
	echo ${cartesRobot[*]} #phase de teste 
	echo "" > tmp/cartePartie
}

#methode qui attend le top depart
waitTopDepart()
{
	#on attend le top depart
	echo "Robot $numeroRobot a recu le top depart." | nc -l -p 9092 | echo "Attente du top départ."
}

#methode qui essaye de faire jouer le robot au meilleur moment
jouerRobot()
{
	#algo pour essayer de faire jouer un robot au bon moment :
	carteCourante=${cartesRobot[0]} 
	
	randomValue=$((1 + $RANDOM % 6))
	time=$(( $(($carteCourante * $randomValue)) / 15 ))
	sleep $time
	
	#pour la phase de test 
	#sleep 0
	
	#ecrit la valeur de la carte dans carteAJouer
	echo $carteCourante > tmp/carteAJouer
	
	#ecrit le num du robot dans numJoueur
	echo $numeroRobot > tmp/numJoueur
	
	onAttend=true
	while [ $onAttend == "true" ]
	do
		echo "Robot $numeroRobot a jouer la carte $carteCourante." | nc localhost 9093 2> /dev/null | echo "Le robot a joué." & onAttend=false
	done

	#on enleve la carte des cartes disponible pour le robot
	retireCarte $carteCourante
}

finGame()
{
	if [ "$(echo $(cat tmp/finGame) | cut -d" " -f1)" == "fin" ];
	then
		echo $(cat tmp/finGame)
		partiFini=true
	fi
}

#methode qui retire la carte envoyer 
retireCarte()
{
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire 
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesTemp 
	
	#on copie les cartes du joueur
	cartesTemp=("${cartesRobot[@]}")
	
	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesRobot
	
	#recupere les bonnes valeurs 
	for i in $(eval echo {0..$((${#cartesTemp[*]} - 1))});
	do	
		if (( "$carteRetirer" != ${cartesTemp[$i]} ));
		then
			cartesRobot+=(${cartesTemp[$i]})	
		fi
	done
}

startGame()
{
	#avant de commencer la partie on attend les cartes
	waitCartes
	
	#quand on a recu les cartes on attend le top depart
	waitTopDepart
	
	while [ $partieFini == "false" ]
	do
		#on verifie si le robot a encores des cartes
		if (( ${#cartesRobot[*]} == 0 ));
		then
			#apres chaque manche on verifie si la partie est fini
			finGame
			
			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					#on reverifie ici avant de redistribuer les cartes
					finGame 
					echo "" > tmp/redistribuer
					onAttend=false
					waitCartes
				fi
			done
		else
			jouerRobot
		fi
	done
}

startGame
